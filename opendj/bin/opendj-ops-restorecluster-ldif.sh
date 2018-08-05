#!/bin/bash -x

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

ldifFile=
hostList=
baseDN=
sharedBackupDir=
backendId=
: ${instanceRoot=}
includeBranch=

USAGE=" Usage: `basename $0` -L ldifFile -i hostList -b includeBranch -n backendId [ -I instanceRoot ] [ -t sharedBackupDir ]"

while getopts hL:i:b:n:I:t:n: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        L)
            ldifFile="$OPTARG"
            ;;
        i)
            hostList="$OPTARG"
            ;;
        b)
            includeBranch="$OPTARG"
            ;;
        t)
            sharedBackupDir="$OPTARG"
            ;;
        n)
            backendId="$OPTARG"
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

if [ ! -f "${ldifFile}" ]; then
    echo "Must pass a ldif file to import"
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

if [ -z "${includeBranch}" ]; then
    echo "Must pass a includeBranch"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${backendId}" ]; then
    echo "Must pass a backendId"
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

baseDN=
for i in "${!OPENDJ_BASE_DNS[@]}"; do
   if [ "${i}" == "${backendId}" ]; then
       baseDN=${OPENDJ_BASE_DNS[${i}]}
   fi
done

if [ -z "${baseDN}" ]; then
    echo "No BackendID found correlating baseDN (${baseDN}) in the local configuration."
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
if [ ! -z "${ldifFile}" ]; then
    echo "#### Importing ldif to primary host"
    ${OPENDJ_HOME_DIR}/bin/import-ldif \
    --hostname ${primaryHost}          \
    --port ${OPENDJ_ADMIN_PORT}        \
    --bindDN "${dirMgrId}"             \
    --bindPassword "${dirMgrPasswd}"   \
    --backendID ${backendId}           \
    --includeBranch ${includeBranch}   \
    --ldifFile ${ldifFile}             \
    --trustall
fi
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

    newBackupDir=$(sudo -u ${OPENDJ_USER} mktemp -d ${OPENDJ_BACKUP_DIR}/backup-XXXXXXXXXXXX)
    archiveName=$(basename ${newBackupDir})
    sudo chmod 755 ${newBackupDir}
    
    echo "#### Taking backup of primary host"
    ${OPENDJ_HOME_DIR}/bin/backup   \
    --hostname ${primaryHost}       \
    --port ${OPENDJ_ADMIN_PORT}     \
    --bindDN "${dirMgrId}"          \
    --bindPassword "${dirMgrPasswd}" \
    --backendID "${backendId}"      \
    --backupDirectory ${newBackupDir} \
    --trustAll
    if [ $? -ne 0 ]; then
        echo "### Seed backup of the primary host could not be created."
        exit 400
    fi
    # if sharedBackupDir is defined, then it's a shared volume for all DJ servers
    # so copy the new backup there, and don't distribute it via scp.
    isShared=$([ -n "${sharedBackupDir}" ] && [ -d "${sharedBackupDir}" ] && echo true || echo false )
    if $isShared; then
        sudo -u ${OPENDJ_USER} mv -v ${newBackupDir} ${sharedBackupDir}/
    fi

    # update all servers 1) copy backup to target host, 2) restore target host
    for idx in $(seq 1 $(($hostCount - 1))); do
        targetHost=${hostArray[${idx}]}

        jobFile=$(mktemp /tmp/$targetHost.XXXXXX)
        chmod +x ${jobFile}

        if $isShared; then
cat <<- EOF > ${jobFile}
#!/bin/bash
echo "#### Restoring (shared) to host ${targetHost}"

${OPENDJ_HOME_DIR}/bin/restore  \
--hostname ${targetHost}        \
--port ${OPENDJ_ADMIN_PORT}     \
--bindDN "${dirMgrId}"          \
--bindPassword "${dirMgrPasswd}" \
--backupDirectory "${sharedBackupDir}/${archiveName}" \
--trustAll
if [ $? -ne 0 ]; then
    echo "### Host (${targetHost}) failed to restore."
fi

rm \$0
EOF
        
        else
cat <<- EOF > ${jobFile}
#!/bin/bash
echo "#### Restoring (scp) to host ${targetHost}"
scp -oStrictHostKeyChecking=no -rp ${newBackupDir} ${targetHost}:${OPENDJ_BACKUP_DIR}/
ssh -oStrictHostKeyChecking=no ${targetHost} "sudo chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_BACKUP_DIR}/${archiveName}"

${OPENDJ_HOME_DIR}/bin/restore  \
--hostname ${targetHost}        \
--port ${OPENDJ_ADMIN_PORT}     \
--bindDN "${dirMgrId}"          \
--bindPassword "${dirMgrPasswd}" \
--backupDirectory "${OPENDJ_BACKUP_DIR}/${archiveName}" \
--trustAll
if [ $? -ne 0 ]; then
    echo "### Host (${targetHost}) failed to restore."
fi

ssh -oStrictHostKeyChecking=no ${targetHost} "sudo rm -rf ${OPENDJ_BACKUP_DIR}/${archiveName}*"
rm \$0
EOF
        fi

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
