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

USAGE="	Usage: `basename $0` dir -D Directory Manager DN -Y Secrets File [ -I instanceRoot ]"

while getopts hD:Y:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
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
localSvcAcctPasswd="${OPENDJ_SVC_PASSWD}"

if [ -z "${localDirMgrPasswd}" ]; then
	echo "Must pass a valid directory manager password or password file"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${localSvcAcctPasswd}" ]; then
	echo "Must pass a valid OpenDJ service account password"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

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

################################################
#
#	Main program
#
################################################

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

echo "#### preparing to seed opendj"
BACKOUT_DATE=$(date +%Y%m%d-%H%M%S)

echo > /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif

for backendName in "${!OPENDJ_BASE_DNS[@]}"; do
    baseDN=${OPENDJ_BASE_DNS[$backendName]}

    echo "#### Expanding templates - zinet-core-backend.ldif for base dn: $baseDN"
    echo >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
    apply_shell_expansion ${SCRIPTPATH}/../ldif/zinet-core-backend.ldif >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif

    echo "#### Expanding templates - zinet-core-aci.ldif"
    echo >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
    apply_shell_expansion ${SCRIPTPATH}/../ldif/zinet-core-aci.ldif >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif

done

if [ ! -z "${OPENDJ_BASE_OPS_DN}" ]; then
    echo "#### Expanding templates - zinet-ops-backend.ldif"
    echo >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
    apply_shell_expansion ${SCRIPTPATH}/../ldif/zinet-ops-backend.ldif >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif

    echo "#### Expanding templates - zinet-ops-aci.ldif"
    echo >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
    apply_shell_expansion ${SCRIPTPATH}/../ldif/zinet-ops-aci.ldif >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
fi

for f in $(find ${SCRIPTPATH}/../ldif/ -name zz-* -type f); do
    echo "#### Expanding templates - ${f}"
    echo >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
    apply_shell_expansion "${f}" >> /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
done

tmpfile=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
echo -n "${localDirMgrPasswd}" > "${tmpfile}"
chmod 400 "${tmpfile}"

echo "#### Updating Directory ${OPENDJ_LDAP_SERVER_URI}"
export LDAPTLS_CACERT=$(find "${ziNetEtcDir}/pki/server" -name "*-cachain.crt" 2>/dev/null | head -1)
ldapmodify -a -vvv -H ${OPENDJ_LDAP_SERVER_URI} -D "${localDirMgrDN}" -y "${tmpfile}" -f /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif 2>&1 | tee /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.log
if [ $? -eq 0 ]; then
    echo "#### Successfully updated the directory. See log file:"
    echo "####      /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.log"
    if [ ! -z "${OPENDJ_SVCS_OPS_DN}" ]; then
        echo "#### Your service account password for uid=service_opendj,${OPENDJ_SVCS_OPS_DN} is:"
        echo "####      ${localSvcAcctPasswd}"
    fi
    rm -f "${tmpfile}"
    rm -f /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
else
    echo "#### Failed to update the directory!! See log file:"
    echo "####      /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.log"
    rm -f "${tmpfile}"
     rm -f /tmp/zinet-opendj-deploy-${BACKOUT_DATE}.ldif
    exit 1
fi