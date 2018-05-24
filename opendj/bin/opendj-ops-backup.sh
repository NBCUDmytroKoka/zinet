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

# Do not allow this script to run with unbound variables!
set -o nounset

SCRIPT=$(readlink -f $0)
SCRIPTPATH=$(dirname ${SCRIPT})
DIRNAME=$(basename ${SCRIPTPATH})

SAVE_DIR=$(pwd)
cd ${SCRIPTPATH}

backupID=
retentionCount=
archiveCommand=
: ${instanceRoot=}

USAGE="	Usage: `basename $0` -i backupID [ -r retentionCount ] [ -I instanceRoot ] [ -a archiveCommand ]"

while getopts hi:r:I:a: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        i)
            backupID="$OPTARG"
            ;;
        r)
            retentionCount="$OPTARG"
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        a)
            archiveCommand="$OPTARG"
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

if [ -z "${backupID}" ]; then
	echo "Must pass a backupID"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

##################################################
#
# Main program
#
##################################################

logger -i -t iamfabric -p info "loading ziNet - $SCRIPT"
source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
	logger -i -t iamfabric -p err "Error reading zinet default runtime"
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

if [[ $(id -un) != "${OPENDJ_USER}" ]]; then
		logger -i -t iamfabric -p err "This script must be run as ${OPENDJ_USER}."
		exit 1
fi

localLDAPBindDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

taskInfo=$(${OPENDJ_HOME_DIR}/bin/manage-tasks   \
            --hostname $(hostname)              \
            --port ${OPENDJ_ADMIN_PORT}         \
            --bindDN "${localLDAPBindDN}"       \
            --bindPassword ${localLDAPBindPW}   \
            --trustall                          \
            --info "${backupID}")

if [ $? -eq 0 ]; then
    while (true); do
        taskStarted=$(${OPENDJ_HOME_DIR}/bin/manage-tasks   \
                    --hostname $(hostname)              \
                    --port ${OPENDJ_ADMIN_PORT}         \
                    --bindDN "${localLDAPBindDN}"       \
                    --bindPassword ${localLDAPBindPW}   \
                    --trustall                          \
                    --summary | grep -w "${backupID}" | grep "Running" )
            if [ ! -z "${taskStarted}" ]; then
                logger -i -t iamfabric -p info "Previous task is not complete, waiting..."
                sleep 1m
            else
                break
            fi
    done

    logger -i -t iamfabric -p info "Cancel the old task"
    ${OPENDJ_HOME_DIR}/bin/manage-tasks \
    --hostname $(hostname)              \
    --port ${OPENDJ_ADMIN_PORT}         \
    --bindDN "${localLDAPBindDN}"       \
    --bindPassword ${localLDAPBindPW}   \
    --trustall                          \
    --cancel "${backupID}" >/dev/null 2>&1

    logger -i -t iamfabric -p info "Scheduling backupID: ${backupID}"
    setDirectives=
    sRecurring=$(grep -w "Status" <<< "${taskInfo}" | awk '{ print $2 }' | tr -d ' ')
    if [ "${sRecurring}" == "Recurring" ]; then
        sSchedule=$(grep "Scheduled Start Time" <<< "${taskInfo}" | awk '{ s = ""; for (i = 4; i <= NF; i++) s = s $i " "; print s }')
        [[ "${sSchedule}" != "${sSchedule% *}" ]] && \
            setDirectives="${setDirectives} --recurringTask '${sSchedule}'" || \
            setDirectives="${setDirectives} --recurringTask  ${sSchedule}"
    fi

    completeEmail=$(grep "Email Upon Completion" <<< "${taskInfo}" | awk '{ print $4 }' | tr -d ' ')
    [ ! -z "${completeEmail}" ] && [ "${completeEmail}" != "None" ] && \
        setDirectives="${setDirectives} --completionNotify  ${completeEmail}"

    failEmail=$(grep "Email Upon Error" <<< "${taskInfo}" | awk '{ print $4 }' | tr -d ' ')
    [ ! -z "${failEmail}" ] && [ "${failEmail}" != "None" ] && \
        setDirectives="${setDirectives} --errorNotify  ${failEmail}"

    sCompress=$(grep -w "Compress" <<< "${taskInfo}" | awk '{ print $2 }' | tr -d ' ')
    [ "${sCompress}" == "true" ] && \
        setDirectives="${setDirectives} --compress"

    sIncremental=$(grep -w "Incremental" <<< "${taskInfo}" | awk '{ print $2 }' | tr -d ' ')
    [ "${sIncremental}" == "true" ] && \
        setDirectives="${setDirectives} --incremental"

    sEncrypt=$(grep -w "Encrypt" <<< "${taskInfo}" | awk '{ print $2 }' | tr -d ' ')
    [ "${sEncrypt}" == "true" ] && \
        setDirectives="${setDirectives} --encrypt"

    sBackupAll=$(grep "Backup All" <<< "${taskInfo}" | awk '{ print $3 }' | tr -d ' ')
    [ "${sBackupAll}" == "true" ] && \
        setDirectives="${setDirectives} --backUpAll"

    sBackupDirectory=$(grep "Backup Directory" <<< "${taskInfo}" | awk '{ print $3 }' | tr -d ' ')
    [ ! -z "${sBackupDirectory}" ] && \
        setDirectives="${setDirectives} --backupDirectory ${sBackupDirectory}"

    sDependencies=$(grep "Dependencies" <<< "${taskInfo}" | awk '{ print $2 }' | tr -d ' ')
    [ ! -z "${sDependencies}" ] && [ "${sDependencies}" != "None" ] && \
        setDirectives="${setDirectives} --dependency ${sDependencies}"

    sFailAction=$(grep "Failed Dependency Action" <<< "${taskInfo}" | awk '{ print $4 }' | tr -d ' ')
    [ ! -z "${sFailAction}" ] && [ "${sFailAction}" != "None" ] && \
        setDirectives="${setDirectives} --failedDependencyAction ${sFailAction}"

    sBackend=$(grep "Backend ID(s)" <<< "${taskInfo}" | awk '{ print $3 }' | tr -d ' ')
    [ ! -z "${sBackend}" ] && \
        setDirectives="${setDirectives} --backendID ${sBackend}"

    logger -i -t iamfabric -p info "Creating archive of backupID: ${backupID} at ${sBackupDirectory}/../archive"
    OLD_DIR=$(pwd)

    cd $(dirname ${sBackupDirectory})
    mkdir archive 2>/dev/null
    BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
    tar -zcvf archive/${backupID}-${BACKUP_DATE}.tgz $(basename ${sBackupDirectory}) >/dev/null 2>&1
    bResult=$?
    cd ${OLD_DIR}

    if [ $bResult -eq 0 ]; then

        # clean up old backup stuff
        rm -rf ${sBackupDirectory}/*
    
        if [ ! -z "${retentionCount}" ]; then
            fileCnt=$(($(ls ${sBackupDirectory}/../archive/${backupID}-*.tgz 2>/dev/null| wc -l)-${retentionCount}))
        
            # fire the archive command, if defined
            [ -n "${archiveCommand}" ] && eval "${archiveCommand}"
        
            # roll off old archives, if any
            [[ $fileCnt -gt 0 ]] && \
                ls ${sBackupDirectory}/../archive/${backupID}-*.tgz | head -${fileCnt} | xargs rm -f
        fi

    else
        logger -i -t iamfabric -p err "Danger: Failed to archive daily backup (${BACKUP_DATE}). "
    fi

    # schedule the new backup
    tmpfile=$(mktemp /tmp/.XXXXXXXXXXXX)

    logger -i -t iamfabric -p info "Scheduling new backup: ${backupID}"
    cat <<- EOF > ${tmpfile}
    ${OPENDJ_HOME_DIR}/bin/backup           \
    --hostname $(hostname)                  \
    --port ${OPENDJ_ADMIN_PORT}             \
    --bindDN "${localLDAPBindDN}"           \
    --bindPassword ${localLDAPBindPW}       \
    --backupID "${backupID}"                \
    $setDirectives                          \
    --trustAll >/dev/null 2>&1
	EOF

    source ${tmpfile}
    bResult=$?
    rm -f ${tmpfile}

    if [ "${bResult}" -eq 0 ]; then
        logger -i -t iamfabric -p info "Successfully cleaned up backupID: ${backupID}"
    else
        logger -i -t iamfabric -p err "Cannot reschedule backupID: ${backupID}"
    fi

else
    logger -i -t iamfabric -p err "Cannot reschedule backupID: ${backupID}"
fi
