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

localTenantId=
localTargetHost=$(hostname)
: ${instanceRoot=}

USAGE="	Usage: `basename $0` -t tenantId [ -n localTargetHost=$(hostname) ] [ -I instanceRoot ]"

while getopts ht:n:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        t)
            localTenantId="$OPTARG"
            ;;
        n)
            localTargetHost="$OPTARG"
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

if [ -z "${localTenantId}" ]; then
	echo "Must pass a valid tenant identifier"
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

echo "#### loading ziNet - $SCRIPT"
source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Error reading zinet default runtime"
	exit 1
fi

# if [[ $(id -un) != "${ziAdmin}" ]]; then
# 		echo "This script must be run as ${ziAdmin}."
# 		exit 1
# fi

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

echo "#### Removing passwd configuration"
rm -rf ${OPENDJ_HOME_DIR}/config/${localTenantId}

##################################################
#### TODO  
##################################################

echo "#### Finished removing passwd config"
cd ${SAVE_DIR}
