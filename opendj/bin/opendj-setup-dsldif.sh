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

USAGE="	Usage: `basename $0` [ -I instanceRoot ]"

while getopts hI: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
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

instanceOpts=
[ ! -z "${instanceRoot}" ] && instanceOpts="-I ${instanceRoot}"

BACKOUT_DATE=$(date +%Y%m%d-%H%M%S)

if [ -z "${OPENDJ_LDAP_SERVER_URI}" ]; then
    echo "#### OPENDJ_LDAP_SERVER_URI is not defined, so no updates will be performed "
    exit 0
fi

echo "#### preparing to local ds config"
for f in ${opendjCfgDir}/schema/*-ds.ldif; do
    echo "#### Expanding ds ldif: $f"
    echo >> /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.ldif
    apply_shell_expansion "${f}" >> /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.ldif
done 2> /dev/null

if [ -f /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.ldif ]; then
    localLDAPBindDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
    localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")
    tmpfile=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
    echo -n "${localLDAPBindPW}" > "${tmpfile}"
    chmod 400 "${tmpfile}"

    echo "#### Updating Directory ${OPENDJ_LDAP_SERVER_URI}"
    export LDAPTLS_CACERT=$(find "${ziNetEtcDir}/pki/server" -name "*-cachain.crt" 2>/dev/null | head -1)
    ldapmodify -c -a -vvv -H ${OPENDJ_LDAP_SERVER_URI} -D "${localLDAPBindDN}" -y "${tmpfile}" -f /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.ldif 2>&1 | tee /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.log
    if [ $? -eq 0 ]; then
        echo "#### Successfully updated the directory with ds config"
        rm -f "${tmpfile}"

        echo "#### Rebuilding indexes"
        sudo ${OPENDJ_TOOLS_DIR}/bin/opendj-ops-rebuild-degraded.sh -a ${instanceOpts}
        echo
        rm -f /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.ldif
    else
        echo "#### Failed to update the directory!!"
        rm -f "${tmpfile}"
        rm -f /tmp/zinet-deploy-dsldif-${BACKOUT_DATE}.ldif
        exit 1
    fi
fi
