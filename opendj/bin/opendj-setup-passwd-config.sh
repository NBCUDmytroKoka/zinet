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

localTargetHostList=$(hostname)
localPolicyInstances=
: ${instanceRoot=}

USAGE="	Usage: `basename $0` [ -p localPolicyInstances ] [ -n localTargetHostList=$(hostname) ] [ -I instanceRoot ]"

while getopts hp:n:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        p)
            localPolicyInstances="$OPTARG"
            ;;
        n)
            localTargetHostList="$OPTARG"
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

################################################
#
#	Functions
#
################################################

apply_shell_expansion() {
    declare file="$1"
    declare data=$(< "$file")
    declare delimiter="__apply_shell_expansion_delimiter__"
    declare command="cat <<$delimiter"$'\n'"$data"$'\n'"$delimiter"
    eval "$command"
}

findAndSource()
{
    rootDir="${1}"
    pattern="${2}"
    enabledList="${3}"
    theInstance="${4}"

    for f in $(find ${rootDir} -name ${pattern} -type f); do

        theFileName=$(basename $f)
        theName=${theFileName%\.*}

        if [ ! -z  "${theInstance}" ]; then
            theName="${theName}-${theInstance}"
        fi

        IFS=' ' read -ra targetHostList  <<< "${localTargetHostList}"
        for localTargetHost in "${targetHostList[@]}"; do
            echo "#### Setting policy ${theName} ==> ${localTargetHost}"

            grep ${theName} <<< "${enabledList}" > /dev/null && { 
                echo "#### Found enabled config: ${theFileName}"
                source $f
                if [ $? -ne 0 ]; then
                    echo "#### ERROR policy ${theName} ==> ${localTargetHost}"    
                    exit 1
                fi    
            } || {
                echo "#### Skipping config: ${theFileName}"
            }
        done
    done
}

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

instPasswdCfgOpts=
[ ! -z "${localPolicyInstances}" ] && instPasswdCfgOpts="-p ${localPolicyInstances}"

instanceOpts=
[ ! -z "${instanceRoot}" ] && instanceOpts="-I ${instanceRoot}"

echo "#### Configuring Validators"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-character-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-dictionary-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-length-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-repeated-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-similarity-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-unique-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-userattr-validator.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}

echo "#### Configuring Notification Handlers"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-notifier-handler.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo

echo "#### Configuring Password Storage Schemes"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-passwd-storage-scheme.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo

echo "#### Configuring Password Policy"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-passwd-policy.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo

echo "#### Configuring Virtual Attribute"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-virtual-attribute.sh -n "${localTargetHostList}" ${instPasswdCfgOpts} ${instanceOpts}
echo

echo "#### Finished setting password policies"
cd ${SAVE_DIR}
