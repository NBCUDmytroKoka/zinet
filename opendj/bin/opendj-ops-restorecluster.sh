#!/bin/bash

################################################
#   Copyright (c) 2015-18 zibernetics, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#   
#       http://www.apache.org/licenses/LICENSE-2.0
#   
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
################################################

SCRIPT=$(readlink -f $0)
SCRIPTPATH=$(dirname ${SCRIPT})
DIRNAME=$(basename ${SCRIPTPATH})

SAVE_DIR=$(pwd)
cd ${SCRIPTPATH}

backupLocation=
hostList=
: ${instanceRoot=}

USAGE=" Usage: `basename $0` -l backupLocation -i hostList [ -I instanceRoot ]"

while getopts hl:i:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        l)
            backupLocation="$OPTARG"
            ;;            
        i)
            hostList="$OPTARG"
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            cd ${SAVE_DIR}
            exit 1
            ;;
    esac
done

if [ ! -d "${backupLocation}" ]; then
    echo "Must pass a backupLocation"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${hostList}" ]; then
    echo "Must pass a hostList"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

backupId=$(grep 'backup_id' ${backupLocation}/backup.info | tail -1 | awk -F= '{print $2}')
backendId=$(grep 'backend_dn' ${backupLocation}/backup.info | awk -F= '{print $3}' | awk -F, '{print $1}')
if [ -z "${backupId}" ] || [ -z "${backendId}" ]; then
    echo "Backup directory does not contain a valid backup - must contain a backup.info file"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

##################################################
#
# Functions
#
##################################################

declare -a pids

interval=10s

waitPids() 
{
    while [ ${#pids[@]} -ne 0 ]; do
        echo "$(date +%Y%m%d-%H:%M:%S) - Waiting for pids: ${pids[@]}"
        local range=$(eval echo {0..$((${#pids[@]}-1))})
        local i
        for i in $range; do
            if ! kill -0 ${pids[$i]} 2> /dev/null; then
                echo "Done -- ${pids[$i]} -- $(date +%Y%m%d-%H%M%S)"
                unset pids[$i]
            fi
        done
        pids=("${pids[@]}")
        [ ${#pids[@]} -ne 0 ] && sleep ${interval}
    done
}

addPid() 
{
    desc=$1
    pid=$2
    echo "$desc -- $pid -- $(date +%Y%m%d-%H%M%S)"
    pids=(${pids[@]} $pid)
}


################################################
#
#   Main program
#
################################################

echo "#### loading ziNet - $SCRIPT"
source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Error reading zinet default runtime"
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

baseDN=${OPENDJ_BASE_DNS[$backendId]}
if [ -z "${baseDN}" ]; then
    echo "Backup ID (${backendId}) does not have a correlating baseDN in the local configuration."
    cd ${SAVE_DIR}
    exit 1
fi

echo "#### Retrieving credentials"
dirMgrId=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
dirMgrPasswd=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

adminId=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Admin")
adminPasswd=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Admin")

echo "#### Processing primary host"
IFS=',' read -a hostArray <<< "${hostList}"
hostCount="${#hostArray[@]}"
primaryHost=${hostArray[0]}

if [ ${hostCount} -gt 1 ]; then
    echo "#### Preparing cluster for restore"
    ${OPENDJ_HOME_DIR}/bin/dsreplication pre-external-initialization \
    --hostname ${primaryHost}   \
    --port ${OPENDJ_ADMIN_PORT} \
    --adminUID ${adminId}       \
    --adminPassword "${adminPasswd}" \
    --baseDN ${baseDN}          \
    --no-prompt                 \
    --trustall
    if [ $? -ne 0 ]; then
        echo "### Error initiating cluster restore (pre-external-initialization)"
        exit 200
    fi
fi

echo "#### Restore to primary host"
${OPENDJ_HOME_DIR}/bin/restore  \
--hostname ${primaryHost}       \
--port ${OPENDJ_ADMIN_PORT}     \
--bindDN "${dirMgrId}"          \
--bindPassword "${dirMgrPasswd}" \
--backupDirectory ${backupLocation} \
--backupID ${backupId}          \
--trustAll
if [ $? -ne 0 ]; then
    echo "### Error restoring backup to primary host"
    if [ ${hostCount} -gt 1 ]; then
        echo "#### Rolling back cluster restore initialization"
        ${OPENDJ_HOME_DIR}/bin/dsreplication post-external-initialization \
        --hostname ${primaryHost}   \
        --port ${OPENDJ_ADMIN_PORT} \
        --adminUID ${adminId}       \
        --adminPassword "${adminPasswd}" \
        --baseDN ${baseDN}          \
        --no-prompt                 \
        --trustall
    fi
    exit 300
fi

if [ ${hostCount} -gt 1 ]; then

    newBackupDir=$(sudo -u ${OPENDJ_USER} mktemp -d /tmp/backup-XXXXXXXXXXXX)
    archiveName=$(basename ${newBackupDir})
    sudo chmod 755 ${newBackupDir}
    
    echo "#### Taking backup of primary host"
    ${OPENDJ_HOME_DIR}/bin/backup   \
    --hostname ${primaryHost}       \
    --port ${OPENDJ_ADMIN_PORT}     \
    --bindDN "${dirMgrId}"          \
    --bindPassword "${dirMgrPasswd}" \
    --backupID "${backupId}"        \
    --backendID "${backendId}"      \
    --backupDirectory ${newBackupDir} \
    --trustAll
    if [ $? -ne 0 ]; then
        echo "### Seed backup of the primary host could not be created."
        exit 400
    fi

    # update all servers 1) copy backup to target host, 2) restore target host
    for idx in $(seq 1 $(($hostCount - 1))); do
        targetHost=${hostArray[${idx}]}

        jobFile=$(mktemp /tmp/$targetHost.XXXXXX)
        chmod +x ${jobFile}
cat <<- EOF >> ${jobFile}
#!/bin/bash
echo "#### Restoring to host ${targetHost}"
scp -oStrictHostKeyChecking=no -rp ${newBackupDir} ${targetHost}:/tmp/
ssh -oStrictHostKeyChecking=no ${targetHost} "sudo chown -R ${OPENDJ_USER}:${OPENDJ_GRP} /tmp/${archiveName}"

${OPENDJ_HOME_DIR}/bin/restore  \
--hostname ${targetHost}        \
--port ${OPENDJ_ADMIN_PORT}     \
--bindDN "${dirMgrId}"          \
--bindPassword "${dirMgrPasswd}" \
--backupDirectory "/tmp/${archiveName}" \
--backupID "${backupId}"        \
--trustAll
if [ $? -ne 0 ]; then
    echo "### Host (${targetHost}) failed to restore."
fi

ssh -oStrictHostKeyChecking=no ${targetHost} "sudo rm -rf /tmp/${archiveName}*"
rm \$0
EOF

        ${jobFile} 2>&1 > ${jobFile}.log &
        addPid "### Starting ${jobFile}" $!
    done

    echo "#### Waiting for restore to complete"
    waitPids

    echo "#### Cleaning up"
    rm -f ${archiveName}

    echo "#### Finalizing cluster for restore"
    ${OPENDJ_HOME_DIR}/bin/dsreplication post-external-initialization \
    --hostname ${primaryHost}   \
    --port ${OPENDJ_ADMIN_PORT} \
    --adminUID ${adminId}       \
    --adminPassword "${adminPasswd}" \
    --baseDN ${baseDN}          \
    --no-prompt                 \
    --trustall
    if [ $? -ne 0 ]; then
        echo "### Error finalizing cluster restore (post-external-initialization)"
        exit 500
    fi
fi
