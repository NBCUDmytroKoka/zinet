#!/bin/bash

################################################
#	Copyright (c) 2015-18 zibernetics, Inc.
#
#	Licensed under the Apache License, Version 2.0 (the "License");
#	you may not use this file except in compliance with the License.
#	You may obtain a copy of the License at
#	
#	    http://www.apache.org/licenses/LICENSE-2.0
#	
#	Unless required by applicable law or agreed to in writing, software
#	distributed under the License is distributed on an "AS IS" BASIS,
#	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#	See the License for the specific language governing permissions and
#	limitations under the License.
#
################################################

SCRIPT=$(readlink -f $0)
SCRIPTPATH=$(dirname ${SCRIPT})
DIRNAME=$(basename ${SCRIPTPATH})

SAVE_DIR=$(pwd)
cd ${SCRIPTPATH}

# if [[ $(id -un) != opendj ]]; then
# 		echo "This script must be run as opendj."
# 		exit 1
# fi

localBackupPolicy=
: ${instanceRoot=}

USAGE="	Usage: `basename $0` -p localBackupPolicy [ -I instanceRoot ]"

while getopts hp:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        p)
            localBackupPolicy="$OPTARG"
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

if [ -z "${localBackupPolicy}" ] || [ ! -f "${localBackupPolicy}" ]; then
	echo "Must pass a backup policy"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

##################################################
#
# Main program
#
##################################################

echo "#### loading ziNet - $SCRIPT"
source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Error reading zinet default runtime"
	exit 1
fi

if [[ $(id -un) != "${ziAdmin}" ]]; then
		echo "This script must be run as ${ziAdmin}."
		exit 1
fi

for f in ${ziNetEtcDir}/*.functions; do source $f; done 2> /dev/null
for f in ${ziNetEtcDir}/*.properties; do source $f; done 2> /dev/null

opendjCfgDir=${ziNetEtcDir}/opendj
if [ ! -z ${instanceRoot} ]; then
    opendjCfgDir="${opendjCfgDir}/${instanceRoot}"
fi

for f in ${opendjCfgDir}/*.functions; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-default.properties; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-override.properties; do source $f; done 2> /dev/null

source ${localBackupPolicy}
if [ $? -ne 0 ]; then
	echo "#### Error reading ${localBackupPolicy}"
	exit 1
fi

localLDAPBindDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

for sBackendName in "${!OPENDJ_BACKUP_CFG[@]}"; do

	echo "#### Processing backend ${sBackendName}"

    xInstanceSettings=${OPENDJ_BACKUP_CFG[$sBackendName]}
    [ -z "${xInstanceSettings}" ] && continue
    IFS=',' read -ra xInstanceArr <<< "${xInstanceSettings}"

    setDirectives=
    sBackupID=
    sCleanUpCron=
    sCleanupRetention=
    sBackupDirectory=
    sBackendID=

    for g in "${xInstanceArr[@]}"; do
        key=${g%%=*}
        value=${g#*=}

        case "$key" in
            target)
                if  [[ "all" == ${value,,} ]]; then
                    sBackendID="all"
                    setDirectives="${setDirectives} --backUpAll"
                else
                    sBackendID="${value}"
                    setDirectives="${setDirectives} --backendID ${value}"
                fi
                ;;
            backupDirectory)
                sBackupDirectory="${OPENDJ_BACKUP_DIR}/${value}"
                mkdir -p "${sBackupDirectory}" 2>/dev/null
                [[ "${value}" != "${value% *}" ]] && \
                setDirectives="${setDirectives} --backupDirectory '${sBackupDirectory}'" || \
                setDirectives="${setDirectives} --backupDirectory  ${sBackupDirectory}"
                ;;
            backupOpt)
                IFS='+' read -ra optsArray <<< "${value}"
                for opt in "${optsArray[@]}"; do
                    setDirectives="${setDirectives} --${opt}"
                done                
                ;;
            cleanupTask)
                # save old crontab
                sCleanUpCron="${value}"
                ;;
            cleanupRetention)
                sCleanupRetention="${value}"
                ;;
            backupID)
                sBackupID="${value}"
                setDirectives="${setDirectives} --backupID ${sBackupID}"
                ;;
            *)
                [[ "${value}" != "${value% *}" ]] && \
                setDirectives="${setDirectives} --${key} '${value}'" || \
                setDirectives="${setDirectives} --${key}  ${value}"
                ;;
        esac
    done

    if [ ! -z "${setDirectives}" ]; then

        if [ -z "${sBackendID}" ]; then
            echo "#### Setting default backendID"        
            sBackendID="all"
            setDirectives="${setDirectives} --backUpAll"
        fi

        if [ -z "${sBackupDirectory}" ]; then
            echo "#### Setting default backup directory"
            sBackupDirectory="${OPENDJ_BACKUP_DIR}"
            setDirectives="${setDirectives} --backupDirectory ${sBackupDirectory}"
        fi

        if [ -z "${sBackupID}" ]; then
            echo "#### Setting default backupID"
            sBackupID="${sBackendID}"
            setDirectives="${setDirectives} --backupID ${sBackupID}"
        fi

        # cancel old backup if one was scheduled
        hasTask=$(${OPENDJ_HOME_DIR}/bin/manage-tasks   \
                    --hostname $(hostname)              \
                    --port ${OPENDJ_ADMIN_PORT}         \
                    --bindDN "${localLDAPBindDN}"       \
                    --bindPassword ${localLDAPBindPW}   \
                    --trustall                          \
                    --info "${sBackupID}")

        if [ $? -eq 0 ]; then
            echo "#### Cancelling old backup"
            ${OPENDJ_HOME_DIR}/bin/manage-tasks \
            --hostname $(hostname)              \
            --port ${OPENDJ_ADMIN_PORT}         \
            --bindDN "${localLDAPBindDN}"       \
            --bindPassword ${localLDAPBindPW}   \
            --trustall                          \
            --cancel "${sBackupID}" >/dev/null 2>&1
        fi

        # schedule the new backup
        tmpfile=$(mktemp /tmp/.XXXXXXXXXXXX)

        echo "#### Scheduling new backup: ${sBackupID}"
        cat <<- EOF > ${tmpfile}
        ${OPENDJ_HOME_DIR}/bin/backup           \
        --hostname $(hostname)                  \
        --port ${OPENDJ_ADMIN_PORT}             \
        --bindDN "${localLDAPBindDN}"           \
        --bindPassword ${localLDAPBindPW}       \
        $setDirectives                          \
        --trustAll >/dev/null 2>&1
EOF

        source ${tmpfile}
        bResult=$?
        rm -f ${tmpfile}

        if [ "${bResult}" -ne 0 ]; then
            echo "#### Error Scheduling a new backup for backendID: ${sBackupID}"
            continue
        fi

        # schedule cleanup tasks
        if [ ! -z "${sCleanUpCron}" ]; then
            tempCron=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
            echo "#### Setting up cleanup job"
            sudo -u ${OPENDJ_USER} crontab -l | grep -v "${sBackupID}" > ${tempCron}
            
            cleanupOpts=
            [ ! -z "${sCleanupRetention}" ] && \
                cleanupOpts="-r ${sCleanupRetention}"

            [ ! -z "${instanceRoot}" ] && \
                cleanupOpts="${cleanupOpts} -I ${instanceRoot}"

            echo "${sCleanUpCron} ${OPENDJ_TOOLS_DIR}/bin/opendj-ops-backup.sh -i ${sBackupID} ${cleanupOpts} >/dev/null 2>&1" >> ${tempCron}
            sudo chmod 666 ${tempCron}
            sudo -u ${OPENDJ_USER} crontab ${tempCron}
            rm -f ${tempCron}
        fi
    else
        echo "#### No parameters were passed to configure the backup"
    fi

done

cd ${SAVE_DIR}
