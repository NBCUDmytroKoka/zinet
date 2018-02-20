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

localTargetHostList=$(hostname)
: ${instanceRoot=}
localUserAttrValidatorList=

USAGE="	Usage: `basename $0` [ -p localUserAttrValidatorList ] [ -n localTargetHostList=$(hostname) ] [ -I instanceRoot ]"

while getopts hn:I:p: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        n)
            localTargetHostList="$OPTARG"
            ;;
        p)
            localUserAttrValidatorList="$OPTARG"
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

if [ -z ${localUserAttrValidatorList} ]; then
    for theName in "${!OPENDJ_PASSWD_ATTRIBUTE[@]}"; do
        [ -z "${localUserAttrValidatorList}" ] && localUserAttrValidatorList="${theName}" || localUserAttrValidatorList="${localUserAttrValidatorList} ${theName}"
    done
fi

if [ -z "${localUserAttrValidatorList}" ]; then
	echo "Must pass a valid UserAttr Validator list"
    exit 0
fi

if [ ! -d ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig ]; then
	echo "Install was not completed. Missing: ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ ! -f ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig/Standard_Setup_UserAttr_Validator ]; then
	echo "Standard_Setup_UserAttr_Validator was not found in ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig."
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

localLDAPBindDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

result=0
IFS=' ' read -ra targetHostList  <<< "${localTargetHostList}"
for localTargetHost in "${targetHostList[@]}"; do
    if [ ! -z "${localUserAttrValidatorList}" ]; then    
        echo "#### Standard_Setup_UserAttr_Validator ($localUserAttrValidatorList) ==> ${localTargetHost}"
        source ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig/Standard_Setup_UserAttr_Validator
        if [ $? -ne 0 ]; then
            echo "#### ERROR executing Standard_Setup_UserAttr_Validator ($localUserAttrValidatorList) ==> ${localTargetHost}"    
            result=1
            break
        fi
    fi
done

cd ${SAVE_DIR}

exit $result
