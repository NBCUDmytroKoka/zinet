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

: ${instanceRoot=}
localNewTopology=false
localUseReplGrps=false

USAGE="	Usage: `basename $0` [ -I instanceRoot ] [ -n =>> localNewTopology ]  [ -r =>> localUseReplGrps ]"

while getopts hI:nr OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        n)
            localNewTopology=true
            ;;
        r)
            localUseReplGrps=true
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            cd ${SAVE_DIR}
            exit 1
            ;;
    esac
done

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
#     OPENDJ_SERVER_1_IP=
#     OPENDJ_SERVER_2_IP=
#     OPENDJ_SERVER_3_IP=
#     ...
#
################################################

replicateSimple()
{
    local baseDN="${1}"

    echo "#### Attempting to start replicateSimple baseDN: $baseDN"
    local replStarted=false
    local replList=
    local primary=
    local slaves=
    local slave=
    local varName=
    local ipIdx=

    if ${localNewTopology}; then
        echo "#### Setting up new replication topology"

        primary=${OPENDJ_SERVER_1_IP}
        if [ -z "${primary}" ]; then
            echo "#### Error - can't find primary server to replicate"
            exit 30
        fi

        # get the remainder of the servers to replicate 
        ipIdx=2
        while true; do
            varName="OPENDJ_SERVER_${ipIdx}_IP"
            slave=${!varName}
            [ -z "${slave}" ] && break

            [ -z "${slaves}" ] && slaves="${slave}" || slaves="${slaves} ${slave}"
            ipIdx=$((ipIdx+1))
        done

        if [ -z "${slaves}" ]; then
            echo "#### Error - can't find slave servers to replicate"
            exit 31
        fi
    else
        echo "#### Adding to existing replication topology"

        # build the list of all servers
        ipIdx=1
        groupServers=
        while true; do
            varName="OPENDJ_SERVER_${ipIdx}_IP"
            theServer=${!varName}
            [ -z "${theServer}" ] && break

            [ -z "${groupServers}" ] && groupServers="${theServer}" || groupServers="${groupServers},${theServer}"
            ipIdx=$((ipIdx+1))
        done

        ### iterate the list of RS servers and find one that's configured. Use it as the seed server
        local hasTopology=false
        local ipIdx=1
        while true; do
            local varName="OPENDJ_SERVER_${ipIdx}_IP"
            targetServer=${!varName}
            [ -z "${targetServer}" ] && break

            echo "#### checking to see if replication server: ${targetServer} can be seed rs"
            replTopologyAll=$(${OPENDJ_HOME_DIR}/bin/dsreplication status \
                    --hostname "${targetServer}"    \
                    --port "${OPENDJ_ADMIN_PORT}"   \
                    --adminUID "${localAdminDN}"    \
                    --adminPassword "${localAdminPasswd}" \
                    --no-prompt --trustall)
            if [ $? -eq 0 ] && [ -n "${replTopologyAll}" ]; then
                ##############################################################################
                # filter Directory Server hosts already in the topology
                replTopologyDS=$(echo "${replTopologyAll}"  | grep "^${baseDN}" | awk -F: '{if ($8 ~ /[0-9]/) {print $2}}' | sort -u | tr -d ' ' | sed '/^$/d')

                # noe set the variables for primary (a replicated server) and slaves (list of new servers that have to be replicated)
                primary="${targetServer}"
                if [ -n "${replTopologyDS}" ]; then
                    # filter directory servers in the current replication group that aren't in the topology
                    slaves=$(comm -13 <(echo "${replTopologyDS}") <(echo "${groupServers}" | tr ',' '\n') | tr -d ' ' | tr '\n' ' ' | xargs echo -n)
                else
                    # otherwise, add the entire list of servers to the replication topology
                    slaves=$(echo "${groupServers}" | tr ',' ' ')
                fi

                hasTopology=true
                break
            fi

            ipIdx=$((ipIdx+1))
        done
        
        if ! $hasTopology; then
            echo "#### Error - can't find existing topology to add replication configuration. Exiting..."
            exit 32
        fi
    fi

    if [ ! -z "${primary}" ]; then
        replList="${primary}"

        for slave in ${slaves}; do
            replList="${replList} ${slave}"
    
            echo "#### Creating Replication baseDN:${baseDN} ==> primary:${primary} to Slave:${slave}"
            ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
            --adminUID "${localAdminDN}"                \
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

            if ${localNewTopology}; then
                echo "#### Initializing Replication baseDN:${baseDN} ==> primary:${primary} to Slave:${slave}"
                ${OPENDJ_HOME_DIR}/bin/dsreplication initialize \
                --adminUID "${localAdminDN}"            \
                --adminPassword "${localAdminPasswd}"   \
                --baseDN "${baseDN}"                    \
                --hostSource "${primary}"               \
                --portSource "${OPENDJ_ADMIN_PORT}"     \
                --hostDestination "${slave}"            \
                --portDestination "${OPENDJ_ADMIN_PORT}" \
                --trustAll --no-prompt
            fi

            replStarted=true
        done
    else
        echo "#### Did not find any replication configuration for ${baseDN}"
    fi

    if ${replStarted}; then
        echo "#### post-replication started = configuring replication domain properties"
        ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-replication-domain.sh -n "${replList}" ${instanceOpts}
        ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-replication-server.sh -n "${replList}" ${instanceOpts}
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
    local replGrpIdx=    
    
    if [ ${localNewTopology} == true ]; then

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
        echo "#### New replication topology - setting up DS ($OPENDJ_DS_SEED) and RS ($OPENDJ_RS_SEED) seed servers."
        ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
        --adminUID "${localAdminDN}"            \
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

    else
        ### iterate the list of RS servers and find one that's configured. Use it as the seed server
        local hasTopology=false
        for replGrpIdx in $(echo "${OPENDJ_REPL_GRPS}" | sed "s/,/ /g"); do
            local varReplGroup="OPENDJ_RS_RG${replGrpIdx}"
            local groupServers=${!varReplGroup}
            [ -z "${groupServers}" ] && continue

            for rsServer in $(echo "${groupServers}" | sed "s/,/ /g"); do
                echo "#### checking to see if replication server: ${rsServer} can be seed rs"
                replTopologyAll=$(${OPENDJ_HOME_DIR}/bin/dsreplication status \
                        --hostname "${rsServer}"        \
                        --port "${OPENDJ_ADMIN_PORT}"   \
                        --adminUID "${localAdminDN}"    \
                        --adminPassword "${localAdminPasswd}" \
                        --no-prompt --trustall)
                if [ $? -eq 0 ] && [ -n "${replTopologyAll}" ]; then
                    ##############################################################################
                    # get Directory Server hosts already in the topology
                    replTopologyDS=$(echo "${replTopologyAll}" | grep "(5)" | grep "^${baseDN}" | awk -F: '{ print (length($6)>0 ? $2:"") }' | sort -u | tr -d ' ' | sed '/^$/d')
                    [ -n "${replTopologyDS}" ] && OPENDJ_DS_SEED=$(echo "${replTopologyDS}" | head -1)

                    ##############################################################################
                    # get replication servers hosts already in the topology
                    replTopologyRS=$(${OPENDJ_HOME_DIR}/bin/dsconfig list-replication-domains \
                            --hostname "${rsServer}"        \
                            --port "${OPENDJ_ADMIN_PORT}"   \
                            --bindDN "${localDirMgrDN}"     \
                            --bindPassword "${localDirMgrPasswd}"         \
                            --provider-name "Multimaster Synchronization" \
                            --property replication-server   \
                            --trustall | grep "${baseDN}" | cut -d: -f2- | tr ',' '\n' | sort -u | tr -d ' ')

                    OPENDJ_RS_SEED="${rsServer}"
                    
                    hasTopology=true
                    break
                fi
            done
            if $hasTopology; then
                break
            fi
        done
        
        if ! $hasTopology; then
            echo "#### Error - can't find existing topology to add replication configuration. Exiting..."
            exit 11
        fi
    fi

    ##############################################################################
    # setup replication servers
    local replStarted=false
    local replList=
    for replGrpIdx in $(echo "${OPENDJ_REPL_GRPS}" | sed "s/,/ /g"); do
        echo "#### Starting to add replication servers in group-id: $replGrpIdx to the topology"
        local varReplGroup="OPENDJ_RS_RG${replGrpIdx}"
        local groupServers=${!varReplGroup}
        [ -z "${groupServers}" ] && continue

        if [ -n "${replTopologyRS}" ]; then
            # filter replication servers in the current replication group that aren't in the topology
            targetServers=$(comm -13 <(echo "${replTopologyRS}") <(echo "${groupServers}" | tr ',' '\n') | tr -d ' ' | sort -u | tr '\n' ' ')
        else
            # otherwise, add the entire list of servers to the replication topology
            targetServers=$(echo "${groupServers}" | tr ',' ' ')
        fi

        for rsServer in ${targetServers}; do
            ### now configure the replication server and seed server
            if [ "${rsServer}" != "${OPENDJ_RS_SEED}" ]; then
                [ -z "${replList}" ] && replList="${rsServer}" || replList="${replList} ${rsServer}"

                echo "#### Adding replication server - group-id: ${replGrpIdx}, rsServer: ${rsServer}, OPENDJ_RS_SEED: ${OPENDJ_RS_SEED}"
                ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
                --adminUID "${localAdminDN}"                \
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

            if [ ${localUseReplGrps} == true ]; then
                echo "#### Setting up set-replication-server-prop - group-id: ${replGrpIdx}, rsServer: ${rsServer}"
                ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-server-prop \
                --hostname "${rsServer}"            \
                --port "${OPENDJ_ADMIN_PORT}"       \
                --bindDN "${localDirMgrDN}"         \
                --bindPassword "${localDirMgrPasswd}"         \
                --provider-name "Multimaster Synchronization" \
                --set group-id:"${replGrpIdx}"      \
                --trustAll --no-prompt
            fi
            replStarted=true
        done
    done

    if ${replStarted}; then
        echo "#### post-replication started = configuring replication server properties"
        ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-replication-server.sh -n "${replList}" ${instanceOpts}
    fi    

    ##############################################################################
    # setup directory servers
    local replStarted=false
    local replList=
    for replGrpIdx in $(echo "${OPENDJ_REPL_GRPS}" | sed "s/,/ /g"); do
        echo "#### Starting to add replicas in group-id: $replGrpIdx to the topology"
        local varReplGroup="OPENDJ_DS_RG${replGrpIdx}"
        local groupServers="${!varReplGroup}"
        [ -z "${groupServers}" ] && continue

        if [ -n "${replTopologyDS}" ]; then
            # filter directory servers in the current replication group that aren't in the topology
            targetServers=$(comm -13 <(echo "${replTopologyDS}") <(echo "${groupServers}" | tr ',' '\n') | tr -d ' ' | tr '\n' ' ')
        else
            # otherwise, add the entire list of servers to the replication topology
            targetServers=$(echo "${groupServers}" | tr ',' ' ')
        fi

        for dsServer in ${targetServers}; do

            if [ "${dsServer}" != "${OPENDJ_DS_SEED}" ]; then
                [ -z "${replList}" ] && replList="${rsServer}" || replList="${replList} ${rsServer}"

                echo "#### Adding replica - baseDN: ${baseDN}, group-id: ${replGrpIdx}, dsServer: ${dsServer}, OPENDJ_RS_SEED: ${OPENDJ_RS_SEED}"
                ${OPENDJ_HOME_DIR}/bin/dsreplication configure \
                --adminUID "${localAdminDN}"                \
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

                # if new replication topology, then initialize the dsServer
                # from the OPENDJ_DS_SEED server
                if ${localNewTopology}; then
                    echo "#### Initializing replica baseDN:${baseDN} ==>  dsServer: ${dsServer}, OPENDJ_DS_SEED: ${OPENDJ_DS_SEED}"
                    ${OPENDJ_HOME_DIR}/bin/dsreplication initialize \
                    --adminUID "${localAdminDN}"            \
                    --adminPassword "${localAdminPasswd}"   \
                    --baseDN "${baseDN}"                    \
                    --hostSource "${OPENDJ_DS_SEED}"        \
                    --portSource "${OPENDJ_ADMIN_PORT}"     \
                    --hostDestination "${dsServer}"         \
                    --portDestination "${OPENDJ_ADMIN_PORT}" \
                    --trustAll --no-prompt
                fi
                replStarted=true
            fi

            # if localUseReplGrps is defined, then set group ids
            if [ ${localUseReplGrps} == true ]; then
                echo "#### Setting up set-replication-domain-prop - baseDN: ${baseDN}, group-id: ${replGrpIdx}, dsServer: ${dsServer}"            
                ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-domain-prop \
                --hostname "${dsServer}"            \
                --port "${OPENDJ_ADMIN_PORT}"       \
                --bindDN "${localDirMgrDN}"         \
                --bindPassword "${localDirMgrPasswd}"         \
                --provider-name "Multimaster Synchronization" \
                --domain-name "${baseDN}"           \
                --set group-id:"${replGrpIdx}"      \
                --trustAll --no-prompt

                echo "#### Setting up set-replication-domain-prop - baseDN: cn=schema, group-id: ${replGrpIdx}, dsServer: ${dsServer}"            
                ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-domain-prop \
                --hostname "${dsServer}"            \
                --port "${OPENDJ_ADMIN_PORT}"       \
                --bindDN "${localDirMgrDN}"         \
                --bindPassword "${localDirMgrPasswd}"         \
                --provider-name "Multimaster Synchronization" \
                --domain-name "cn=schema"           \
                --set group-id:"${replGrpIdx}"      \
                --trustAll --no-prompt

                echo "#### Setting up set-replication-domain-prop - baseDN: cn=admin data, group-id: ${replGrpIdx}, dsServer: ${dsServer}"            
                ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-domain-prop \
                --hostname "${dsServer}"            \
                --port "${OPENDJ_ADMIN_PORT}"       \
                --bindDN "${localDirMgrDN}"         \
                --bindPassword "${localDirMgrPasswd}"         \
                --provider-name "Multimaster Synchronization" \
                --domain-name "cn=admin data"       \
                --set group-id:"${replGrpIdx}"      \
                --trustAll --no-prompt
            fi
        done
    done

    if ${replStarted}; then
        echo "#### post-replication started = configuring replication domain properties"
        ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-replication-domain.sh -n "${replList}" ${instanceOpts}
    fi    
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

if [[ $(id -un) != "${ziAdmin}" ]]; then
    echo "This script must be run as ${ziAdmin}."
    exit 99
fi

localDirMgrDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
if [ -z "${localDirMgrDN}" ]; then
	echo "localDirMgrDN not found"
    exit 100
fi

localDirMgrPasswd=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")
if [ -z "${localDirMgrPasswd}" ]; then
	echo "localDirMgrPasswd not found"
    exit 101
fi

localAdminDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Admin")
if [ -z "${localAdminDN}" ]; then
	echo "localAdminDN not found"
    exit 102
fi

localAdminPasswd=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Admin")
if [ -z "${localAdminPasswd}" ]; then
	echo "localAdminPasswd not found"
    exit 103
fi

wasProcessed=false
for theBackend in "${!OPENDJ_BASE_DNS[@]}"; do
    theBaseDN=${OPENDJ_BASE_DNS[$theBackend]}

    if [ -n "${OPENDJ_RS_SEED}" ]; then
        replicateWithExternalRS "${theBaseDN}"
    else
        replicateSimple "${theBaseDN}"
    fi

    wasProcessed=true
done

if [ ${wasProcessed} == false ]; then
    for theBackend in "${!OPENDJ_REPL_BASE_DNS[@]}"; do
        theBaseDN=${OPENDJ_REPL_BASE_DNS[$theBackend]}

        if [ -n "${OPENDJ_RS_SEED}" ]; then
            replicateWithExternalRS "${theBaseDN}"
        else
            replicateSimple "${theBaseDN}"
        fi
    done
fi

echo "#### Showing Replication Status"
${OPENDJ_HOME_DIR}/bin/dsreplication status \
    --port ${OPENDJ_ADMIN_PORT}     \
    --adminUID "${localAdminDN}"    \
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

