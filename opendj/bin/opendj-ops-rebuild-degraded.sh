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
    exit 1
fi

: ${instanceRoot=}
localBackendIdxList=
localTargetHostList=$(hostname)
localOfflineMode=false
localRebuildMode=--rebuildDegraded

USAGE="	Usage: `basename $0` [ -I instanceRoot ] [ -n localTargetHostList=$(hostname) ] [ -m (offline) ] [ -a (rebuildall) ]"

while getopts hI:n:ma OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        n)
            localTargetHostList="$OPTARG"
            ;;
        m)
            localOfflineMode=true
            ;;
        a)
            localRebuildMode=--rebuildAll
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

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

for f in ${ziNetEtcDir}/*.functions; do source $f; done 2> /dev/null
for f in ${ziNetEtcDir}/*.properties; do source $f; done 2> /dev/null

opendjCfgDir=${ziNetEtcDir}/opendj
if [ ! -z ${instanceRoot} ]; then
    opendjCfgDir="${opendjCfgDir}/${instanceRoot}"
fi

for f in ${opendjCfgDir}/*.functions; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-default.properties; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-override.properties; do source $f; done 2> /dev/null

localLDAPBindDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

time {

if ${localOfflineMode}; then
    echo "#### Building degraded indicies offline"

    ${OPENDJ_TOOLS_DIR}/bin/opendj-ops-control.sh stopWait ${instanceRoot}

    for backendId in "${!OPENDJ_BASE_DNS[@]}"; do
        baseDN=${OPENDJ_BASE_DNS[$backendId]}

        echo "#### Processing baseDN: ${baseDN}"
        ${OPENDJ_HOME_DIR}/bin/rebuild-index --baseDN "${baseDN}" --rebuildDegraded --offline
        echo

        echo "#### Current status"
        ${OPENDJ_HOME_DIR}/bin/backendstat show-index-status --backendID ${backendId} --baseDN ${baseDN}
    done

    ${OPENDJ_TOOLS_DIR}/bin/opendj-ops-control.sh startWait ${instanceRoot}
else
    echo "#### Building degraded indicies online"

    IFS=' ' read -ra targetHostList  <<< "${localTargetHostList}"
    for localTargetHost in "${targetHostList[@]}"; do

        echo "#### Rebuilding degraded index for host: ${localTargetHost}"
        for backendId in "${!OPENDJ_BASE_DNS[@]}"; do
            baseDN=${OPENDJ_BASE_DNS[$backendId]}

            echo "#### Processing baseDN: ${baseDN}"
            ${OPENDJ_HOME_DIR}/bin/rebuild-index    \
                --hostname "${localTargetHost}"     \
                --port ${OPENDJ_ADMIN_PORT}         \
                --bindDN "${localLDAPBindDN}"       \
                --bindPassword "${localLDAPBindPW}" \
                --baseDN "${baseDN}"                \
                --rebuildDegraded                   \
                --trustAll
        done
    done

fi

}

cd ${SAVE_DIR}

