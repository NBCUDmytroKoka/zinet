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
localNewTopology=false

USAGE="	Usage: `basename $0` -D Directory Manager DN -Y Secrets File [ -I instanceRoot ] [ -n =>> localNewTopology ]"

while getopts hD:Y:I:n OPT; do
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
        n)
            localNewTopology=true
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

################################################
#
#	replicateSimple
#   Handles simple replication of a topology, the combines replication servers and
#   directory servers (on the same host) together.
#     OPENDJ_REPLGRP1_PRIMARY=
#     OPENDJ_REPLGRP1_SLAVE1=
#     OPENDJ_REPLGRP1_SLAVE2=
#     OPENDJ_REPLGRP1_SLAVE3=
#     OPENDJ_REPLGRP1_SLAVE4=
#     OPENDJ_REPLGRP1_SLAVE5=
#
#   PRIMARY is the address of the main replication server to configure the cluster
#   REPLGRP* is a replication topology where groups of servers are distinct. 
#   This can be increasing, e.g. OPENDJ_REPLGRP1, OPENDJ_REPLGRP2. NOTE: each "group"
#   actually represents a separate replication topology
#   SLAVE* is a node in the replication topology
#
################################################

replicateSimple()
{
    local baseDN="${1}"

    echo "#### Attempting to start replicateSimple baseDN: $baseDN"
    local replStarted=false
    local replList=

    local replGrpIdx=1
    while true; do
        local varReplGroup="OPENDJ_REPLGRP${replGrpIdx}"
        replGrpIdx=$((replGrpIdx+1))

        local varName="${varReplGroup}_PRIMARY"
        local primary=${!varName}

        if [ ! -z "${primary}" ]; then
            replList="${primary}"

            local slaveIdx=1

            while true; do
                varName="${varReplGroup}_SLAVE${slaveIdx}"
                local slave=${!varName}
                slaveIdx=$((slaveIdx+1))

                if [ ! -z "${slave}" ]; then
                    replList="${replList} ${slave}"
                
                    echo "#### Creating Replication baseDN:${baseDN} ==> Primary:${primary} to Slave:${slave}"
                    ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
                    --adminUID admin                            \
                    --adminPassword "${localAdminPasswd}"       \
                    --baseDN "${baseDN}"                        \
                    --host1 "${primary}"                        \
                    --port1 "${OPENDJ_ADMIN_PORT}"              \
                    --bindDN1 "${localDirMgrDN}"                \
                    --bindPassword1 "${localDirMgrPasswd}"      \
                    --secureReplication1                        \
                    --replicationPort1 "${OPENDJ_REPL_PORT}"    \
                    --host2 "${slave}"                          \
                    --port2 "${OPENDJ_ADMIN_PORT}"              \
                    --bindDN2 "${localDirMgrDN}"                \
                    --bindPassword2 "${localDirMgrPasswd}"      \
                    --secureReplication2                        \
                    --replicationPort2 "${OPENDJ_REPL_PORT}"    \
                    --trustAll --no-prompt

                    echo "#### Initializing Replication baseDN:${baseDN} ==> Primary:${primary} to Slave:${slave}"
                    ${OPENDJ_HOME_DIR}/bin/dsreplication initialize \
                    --adminUID admin                        \
                    --adminPassword "${localAdminPasswd}"   \
                    --baseDN "${baseDN}"                    \
                    --hostSource "${primary}"               \
                    --portSource "${OPENDJ_ADMIN_PORT}"     \
                    --hostDestination "${slave}"            \
                    --portDestination "${OPENDJ_ADMIN_PORT}" \
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
        echo "#### post-replication started = configuring replication domain properties"
        ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-replication-domain.sh -n "${replList}" ${instanceOpts}
    fi
}

################################################
#
#	replicateWithExternalRS
#   Sets up an advanced replication server topology
#   
################################################

replicateWithExternalRS()
{
    local baseDN="${1}"

    echo "#### Attempting to start replicateWithExternalRS baseDN: $baseDN"

    ## gather all servers in the replication topology for the target baseDN
    local replTopologyDS=
    local replTopologyRS=
    local targetServers=
    local replTopologyAll=
    
    if [ ${localNewTopology} == true ]; then
        echo "#### New replication topology - setting up DS and RS seed servers."

        ##############################################################################
        ## OPENDJ_RS_SEED and OPENDJ_DS_SEED are special variables.
        ## for a brand new topology setup, these are the servers that are picked as the
        ## reference servers from which all others will be initialized. 
        ##############################################################################

        if [ -z "${OPENDJ_DS_SEED}" ] || [ -z "${OPENDJ_RS_SEED}" ]; then
            echo "#### Error: OPENDJ_DS_SEED or OPENDJ_RS_SEED is undefined when initializing a new topology"
            exit 10
        fi

        ##############################################################################
        ## initialize the replication servers and directory servers
        ##############################################################################
        ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
        --adminUID admin                        \
        --adminPassword "${localAdminPasswd}"   \
        --baseDN "${baseDN}"                    \
        --host1 "${OPENDJ_RS_SEED}"             \
        --port1 "${OPENDJ_ADMIN_PORT}"          \
        --bindDN1 "${localDirMgrDN}"            \
        --bindPassword1 "${localDirMgrPasswd}"  \
        --secureReplication1                    \
        --replicationPort1 "${OPENDJ_REPL_PORT}" \
        --onlyReplicationServer1                \
        --host2 "${OPENDJ_DS_SEED}"             \
        --port2 "${OPENDJ_ADMIN_PORT}"          \
        --bindDN2 "${localDirMgrDN}"            \
        --bindPassword2 "${localDirMgrPasswd}"  \
        --secureReplication2                    \
        --noReplicationServer2                  \
        --trustAll --no-prompt
        
        ${OPENDJ_HOME_DIR}/bin/dsreplication initialize-all \
        --adminUID admin                        \
        --adminPassword "${localAdminPasswd}"   \
        --baseDN "${baseDN}"                    \
        --hostname "${OPENDJ_DS_SEED}"          \
        --port "${OPENDJ_ADMIN_PORT}"           \
        --trustAll --no-prompt        
        
    else    
        ### iterate the list of RS servers and find one that's configured. Use it as the seed server
        bDone=false
        for replGrpIdx in $(echo "${OPENDS_REPL_GRPS}" | sed "s/,/ /g"); do
            local varReplGroup="OPENDJ_RS_RG${replGrpIdx}"
            local groupServers=${!varReplGroup}
            [ -z "${groupServers}" ] && continue

            for rsServer in $(echo "${groupServers}" | sed "s/,/ /g"); do
                echo "#### Finding replication server - rsServer: ${rsServer}"
                replTopologyAll-$(${OPENDJ_HOME_DIR}/bin/dsreplication status \
                        --hostname "${rsServer}"    \
                        --adminUID admin            \
                        --adminPassword "${localAdminPasswd}" \
                        --no-prompt --trustall | grep "${baseDN}")
                if [ $? -eq 0 ] && [ -n "${replTopologyAll}" ]; then
                    ##############################################################################
                    # filter Directory Server hosts already in the topology
                    replTopologyDS=$(echo "${replTopologyAll}" | awk -F: '{ print (length($6)>0 ? $2:"") }' | sort -u | tr -d ' ' | sed '/^$/d')
                    [ -n "${replTopologyDS}" ] && OPENDJ_DS_SEED=$(echo "${replTopologyDS}" | head -1)

                    ##############################################################################
                    # filter replication servers hosts already in the topology
                    replTopologyRS=$(echo "${replTopologyAll}" | grep "${OPENDJ_REPL_PORT}" | awk -F: '{ print $2}' | sort -u  | tr -d ' ')
                    OPENDJ_RS_SEED="${rsServer}"
                    
                    bDone=true
                    break
                fi
            done
            if $bDone; then
                break
            fi
        done
        
        if ! $bDone; then
            echo "#### Error - can't find existing topology to add replication configuration. Exiting..."
            exit 20
        fi
    fi

    ##############################################################################
    echo "#### Starting to add replication servers to the topology"
    for replGrpIdx in $(echo "${OPENDS_REPL_GRPS}" | sed "s/,/ /g"); do
        local varReplGroup="OPENDJ_RS_RG${replGrpIdx}"
        local groupServers=${!varReplGroup}
        [ -z "${groupServers}" ] && continue

        if [ -n "${replTopologyRS}" ]; then
            # filter replication servers in the current replication group that aren't in the topology
            targetServers=$(comm -13 <(echo "${replTopologyRS}") <(echo "${groupServers}" | tr ',' '\n') | tr -d ' ' | tr '\n' ' ')
        else
            # otherwise, add the entire list of servers to the replication topology
            targetServers=$(echo "${groupServers}" | tr ',' ' ')
        fi

        for rsServer in ${targetServers}; do
            echo "#### Adding replication server - group-id: ${replGrpIdx}, rsServer: ${rsServer}, OPENDJ_DS_SEED: ${OPENDJ_DS_SEED}"

            echo "#### Setting up set-replication-server-prop"
            ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-server-prop \
            --port ${OPENDJ_ADMIN_PORT}         \
            --hostname ${rsServer}              \
            --bindDN "${localDirMgrDN}"         \
            --bindPassword "${localDirMgrPasswd}"         \
            --provider-name "Multimaster Synchronization" \
            --set group-id:${replGrpIdx}        \
            --trustAll --no-prompt

            ### now configure the replication server and seed server
            if [ "${rsServer}" != "${OPENDJ_RS_SEED}" ]; then
                echo "#### Executing dsreplication configure"

                ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
                --adminUID admin                            \
                --adminPassword "${localAdminPasswd}"       \
                --baseDN "${baseDN}"                        \
                --host1 "${OPENDJ_RS_SEED}"                 \
                --port1 "${OPENDJ_ADMIN_PORT}"              \
                --bindDN1 "${localDirMgrDN}"                \
                --bindPassword1 "${localDirMgrPasswd}"      \
                --secureReplication1                        \
                --onlyReplicationServer1                    \
                --host2 "${rsServer}"                       \
                --port2 "${OPENDJ_ADMIN_PORT}"              \
                --bindDN2 "${localDirMgrDN}"                \
                --bindPassword2 "${localDirMgrPasswd}"      \
                --replicationPort2 "${OPENDJ_REPL_PORT}"    \
                --onlyReplicationServer2                    \
                --secureReplication2                        \
                --trustAll --no-prompt                
            fi        
        done
    done

    ##############################################################################
    echo "#### Starting to add replicas to the topology"
    local replGrpIdx=
    for replGrpIdx in $(echo "${OPENDS_REPL_GRPS}" | sed "s/,/ /g"); do
        local varReplGroup="OPENDJ_DS_RG${replGrpIdx}"
        local groupServers=${!varReplGroup}
        [ -z "${groupServers}" ] && continue

        if [ -n "${replTopologyDS}" ]; then
            # filter directory servers in the current replication group that aren't in the topology
            targetServers=$(comm -13 <(echo "${replTopologyDS}") <(echo "${groupServers}" | tr ',' '\n') | tr -d ' ' | tr '\n' ' ')
        else
            # otherwise, add the entire list of servers to the replication topology
            targetServers=$(echo "${groupServers}" | tr ',' ' ')
        fi

        for dsServer in ${targetServers}; do
            echo "#### Adding replica - baseDN: ${baseDN}, group-id: ${replGrpIdx}, dsServer: ${dsServer}, OPENDJ_RS_SEED: ${OPENDJ_RS_SEED}"

            # set replication group
            echo "#### Setting up set-replication-domain-prop"
            ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-domain-prop \
            --port "${OPENDJ_ADMIN_PORT}"       \
            --hostname "${dsServer}"            \
            --bindDN "${localDirMgrDN}"         \
            --bindPassword "${localDirMgrPasswd}"         \
            --provider-name "Multimaster Synchronization" \
            --domain-name "${baseDN}"           \
            --set group-id:"${replGrpIdx}"      \
            --trustAll --no-prompt

            if [ "${dsServer}" != "${OPENDJ_DS_SEED}" ]; then
                echo "#### Executing dsreplication configure"

                ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
                --adminUID admin                            \
                --adminPassword "${localAdminPasswd}"       \
                --baseDN "${baseDN}"                        \
                --host1 "${dsServer}"                       \
                --port1 "${OPENDJ_ADMIN_PORT}"              \
                --bindDN1 "${localDirMgrDN}"                \
                --bindPassword1 "${localDirMgrPasswd}"      \
                --noReplicationServer1                      \
                --secureReplication1                        \
                --host2 "${OPENDJ_RS_SEED}"                 \
                --port2 "${OPENDJ_ADMIN_PORT}"              \
                --bindDN2 "${localDirMgrDN}"                \
                --bindPassword2 "${localDirMgrPasswd}"      \
                --replicationPort2 "${OPENDJ_REPL_PORT}"    \
                --onlyReplicationServer2                    \
                --secureReplication2                        \
                --trustAll --no-prompt

                if ${localNewTopology}; then
                    echo "#### Initializing Replication baseDN:${baseDN} ==> OPENDJ_DS_SEED:${OPENDJ_DS_SEED} to dsServer:${dsServer}"
                    ${OPENDJ_HOME_DIR}/bin/dsreplication initialize \
                    --adminUID admin                        \
                    --adminPassword "${localAdminPasswd}"   \
                    --baseDN "${baseDN}"                    \
                    --hostSource "${OPENDJ_DS_SEED}"        \
                    --portSource "${OPENDJ_ADMIN_PORT}"     \
                    --hostDestination "${dsServer}"         \
                    --portDestination "${OPENDJ_ADMIN_PORT}" \
                    --trustAll --no-prompt
                fi
            fi            
        done
    done
}

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


for theBackend in "${!OPENDJ_BASE_DNS[@]}"; do
    theBaseDN=${OPENDJ_BASE_DNS[$theBackend]}

    if [ -n "${OPENDJ_RS_SEED}" ]; then
        replicateWithExternalRS "${theBaseDN}" 
    else
        replicateSimple "${theBaseDN}"
    fi
done

echo "#### Showing Replication Status"
${OPENDJ_HOME_DIR}/bin/dsreplication status \
    --port ${OPENDJ_ADMIN_PORT}         \
    --adminUID admin                    \
    --adminPassword "${localAdminPasswd}" \
    -X -n 2> /dev/null

echo "#### Showing Replication Domains"
${OPENDJ_HOME_DIR}/bin/dsconfig list-replication-domains \
    --port ${OPENDJ_ADMIN_PORT}                     \
    --bindDN "${localDirMgrDN}"                     \
    --bindPassword "${localDirMgrPasswd}"           \
    --provider-name "Multimaster Synchronization"   \
    --no-prompt --trustAll

echo "#### Finished setting up OpenDJ"

cd ${SAVE_DIR}
