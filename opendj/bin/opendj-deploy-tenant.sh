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
: ${instanceRoot=}
localSecretsFile=
localDirMgrDN=
tenantSecretFile=

USAGE="	Usage: `basename $0` -t tenantId -D Directory Manager DN -Y localSecretsFile [ -I instanceRoot ] [ -P tenantSecretFile ]"

while getopts ht:I:D:Y:P: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        t)
            localTenantId="$OPTARG"
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        D)
            localDirMgrDN="$OPTARG"
            ;;
        Y)
            localSecretsFile="$OPTARG"
            ;;
        P)
            tenantSecretFile="$OPTARG"
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

if [ -z "${localTenantId}" ]; then
	echo "Must pass a valid tenandId"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

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
localLDAPBindPW="${OPENDJ_DS_DIRMGRPASSWD}"
if [ -z "${localLDAPBindPW}" ]; then
	echo "Must pass a valid admin bind password"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ ! -z "${tenantSecretFile}" ] && [ -f "${tenantSecretFile}" ]; then
    source "${tenantSecretFile}"
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

BACKOUT_DATE=$(date +%Y%m%d-%H%M%S)

echo "#### preparing to deploy"

# get tenant OpenDJ service account password
svcPasswdName="OPENDJ_${localTenantId}_SVC_PASSWD"
localTenantSvcPasswd="${!svcPasswdName}"
[ -z "${localTenantSvcPasswd}" ] && localTenantSvcPasswd=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w32 | head -n1)

if [ ! -d ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif ]; then
	echo "Install was not completed. Missing: ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ ! -z "${OPENDJ_TENANT_HOME}" ]; then
    echo "#### Expanding tenant templates - zinet-tenants-backend.ldif"
    apply_shell_expansion ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif/zinet-tenants-backend.ldif > /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
    chmod 400 /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif

    echo "#### Expanding tenant templates - zinet-tenants-aci.ldif"
    echo >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
    apply_shell_expansion ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif/zinet-tenants-aci.ldif >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
fi

for f in ${opendjCfgDir}/schema/*-schema.ldif; do
    echo "#### Expanding tenant custom schema: $f"
    echo >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
    apply_shell_expansion "${f}" >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
done 2> /dev/null

for f in ${opendjCfgDir}/schema/*-backend.ldif; do
    echo "#### Expanding tenant custom backend: $f"
    echo >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
    apply_shell_expansion "${f}" >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
done 2> /dev/null

for f in ${opendjCfgDir}/schema/*-aci.ldif; do
    echo "#### Expanding tenant custom aci: $f"
    echo >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
    apply_shell_expansion "${f}" >> /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
done 2> /dev/null

tmpfile=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
echo -n "${localLDAPBindPW}" > "${tmpfile}"
chmod 400 "${tmpfile}"

echo "#### Updating Directory ${OPENDJ_LDAP_SERVER_URI}"
export LDAPTLS_CACERT=$(find "${ziNetEtcDir}/pki/server" -name "*-cachain.crt" 2>/dev/null | head -1)
ldapmodify -c -a -vvv -H ${OPENDJ_LDAP_SERVER_URI} -D "${localDirMgrDN}" -y "${tmpfile}" -f /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif 2>&1 | tee /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.log
if [ $? -eq 0 ]; then
    echo "#### Successfully updated the directory. See log file:"
    echo "####      /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.log"
    if [ ! -z "${OPENDJ_TENANT_HOME}" ]; then
        echo "#### Your tenant service account password for uid=service_opendj,${OPENDJ_SVCS_TENANT_DN} is:"
        echo "####      ${localTenantSvcPasswd}"

        echo >> ${opendjCfgDir}/.netrc
        echo "machine OpenDJ_Service-${localTenantId}" >> ${opendjCfgDir}/.netrc
        echo "    login uid=service_opendj,${OPENDJ_SVCS_TENANT_DN}" >> ${opendjCfgDir}/.netrc
        echo "    password ${localTenantSvcPasswd}" >> ${opendjCfgDir}/.netrc
    fi
    rm -f "${tmpfile}"
    rm -f /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
else
    echo "#### Failed to update the directory!! See log file:"
    echo "####      /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.log"
    rm -f "${tmpfile}"
    rm -f /tmp/zinet-deploy-tenant-${localTenantId}-${BACKOUT_DATE}.ldif
    exit 1
fi
