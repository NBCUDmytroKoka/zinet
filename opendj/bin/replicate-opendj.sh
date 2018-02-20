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

if [[ $(id -un) != root ]]; then
		echo "This script must be run as root."
		exit
fi

localDirMgrDN=
localSecretsFile=
: ${instanceRoot=}

USAGE="	Usage: `basename $0` -D Directory Manager DN -Y Secrets File [ -I instanceRoot ]"

while getopts hD:Y:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        D)
            localDirMgrDN="$OPTARG"
            ;;
        Y)
            localSecretsFile="$OPTARG"
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

if [ -z "${localDirMgrDN}" ]; then
	echo "Must pass a valid admin bind dn"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${localSecretsFile}" ] || [ ! -f "${localSecretsFile}" ]; then
	echo "Must pass a valid secrets file"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

source "${localSecretsFile}"
localDirMgrPasswd="${OPENDJ_DS_DIRMGRPASSWD}"
localAdminPasswd="${OPENDJ_ADM_PASSWD}"

if [ -z "${localDirMgrPasswd}" ]; then
	echo "Must pass a valid directory manager password or password file"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${localAdminPasswd}" ]; then
	echo "Must pass a valid admin password or password file"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

################################################
#
#	Functions
#
################################################


##################################################
#
# Main program
#
##################################################

OPENDJ_HOME_DIR=
declare -A OPENDJ_BASE_DNS=()

echo "#### loading ziNet - $SCRIPT"
source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Error reading zinet default runtime"
	exit 1
fi

for f in ${ziNetEtcDir}/*.functions; do source $f; done 2> /dev/null
for f in ${ziNetEtcDir}/*.properties; do source $f; done 2> /dev/null

opendjCfgDir=${ziNetEtcDir}/opendj
[ ! -z ${instanceRoot} ] &&  opendjCfgDir="${opendjCfgDir}/${instanceRoot}"

instanceOpts=
[ ! -z "${instanceRoot}" ] && instanceOpts="-I ${instanceRoot}"

for f in ${opendjCfgDir}/*.functions; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-default.properties; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-override.properties; do source $f; done 2> /dev/null

echo "##### Setting up replication"
for backendName in "${!OPENDJ_BASE_DNS[@]}"; do
    baseDN=${OPENDJ_BASE_DNS[$backendName]}

    echo "#### Attempting to start replication: $backendName with baseDN: $baseDN"
    replStarted=false
    localHostList=

    grpIdx=1
    while true; do
        varReplGroup="OPENDJ_REPLGRP${grpIdx}"
        grpIdx=$((grpIdx+1))

        varName="${varReplGroup}_PRIMARY"
        primary=${!varName}

        if [ ! -z "${primary}" ]; then
            localHostList="${primary}"

            slaveIdx=1

            while true; do
                varName="${varReplGroup}_SLAVE${slaveIdx}"
                slave=${!varName}
                slaveIdx=$((slaveIdx+1))

                if [ ! -z "${slave}" ]; then
                    localHostList="${localHostList} ${slave}"
                
                    echo "#### Creating Replication baseDN:${baseDN} ==> Primary:${primary} to Slave:${slave}"
                    sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
                    --adminUID admin                            \
                    --adminPassword ${localAdminPasswd}         \
                    --baseDN "${baseDN}"                        \
                    --host1 ${primary}                          \
                    --port1 ${OPENDJ_ADMIN_PORT}                \
                    --bindDN1 "${localDirMgrDN}"                \
                    --bindPassword1 ${localDirMgrPasswd}        \
                    --replicationPort1 ${OPENDJ_REPL_PORT}      \
                    --secureReplication1                        \
                    --host2 ${slave}                            \
                    --port2 ${OPENDJ_ADMIN_PORT}                \
                    --bindDN2 "${localDirMgrDN}"                \
                    --bindPassword2 ${localDirMgrPasswd}        \
                    --replicationPort2 ${OPENDJ_REPL_PORT}      \
                    --secureReplication2                        \
                    --trustAll --no-prompt

                    echo "#### Initializing Replication baseDN:${baseDN} ==> Primary:${primary} to Slave:${slave}"
                    sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/bin/dsreplication initialize \
                    --adminUID admin                        \
                    --adminPassword ${localAdminPasswd}     \
                    --baseDN "${baseDN}"                    \
                    --hostSource ${primary}                 \
                    --portSource ${OPENDJ_ADMIN_PORT}       \
                    --hostDestination ${slave}              \
                    --portDestination ${OPENDJ_ADMIN_PORT}  \
                    --trustAll --no-prompt

                    replStarted=true
                else
                    break
                fi
            done
        else
            echo "#### Did not find any replication configuration for ${baseDN} / ${varName}"
            break
        fi
    done

    if ${replStarted}; then
#         echo "#### Initializing Replication Group @ baseDN:${baseDN} from Primary:${primary}"
#         sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/bin/dsreplication initialize-all \
#         --adminUID admin                    \
#         --adminPassword ${localAdminPasswd} \
#         --baseDN "${baseDN}"                \
#         --hostname ${primary}               \
#         --port ${OPENDJ_ADMIN_PORT}         \
#         --trustAll                          \
#         --no-prompt

        echo "#### post-replication started = configuring replication domain properties"
        sudo -u ${OPENDJ_USER} ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-replication-domain.sh -n "${localHostList}" ${instanceOpts}
    fi
done

echo "#### Showing Replication Status"
sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/bin/dsreplication status \
    --port ${OPENDJ_ADMIN_PORT}         \
    --adminUID admin                    \
    --adminPassword ${localAdminPasswd} \
    -X -n 2> /dev/null

echo "#### Showing Replication Domains"
sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/bin/dsconfig list-replication-domains \
    --port ${OPENDJ_ADMIN_PORT}                     \
    --bindDN "${localDirMgrDN}"                     \
    --bindPassword ${localDirMgrPasswd}             \
    --provider-name "Multimaster Synchronization"   \
    --no-prompt --trustAll

echo "#### Finished setting up OpenDJ"

cd ${SAVE_DIR}
