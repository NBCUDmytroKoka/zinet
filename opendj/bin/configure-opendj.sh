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

localHostName=$(hostname)
localDirMgrDN=
localDirMgrPasswd=
: ${instanceRoot=}
localAdminPasswd=
localSecretsFile=

USAGE="	Usage: `basename $0` -D Directory Manager DN -Y localSecretsFile [ -I instanceRoot ]"

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

instanceOpts=
[ ! -z "${instanceRoot}" ] && instanceOpts="-I ${instanceRoot}"

fileList="$(ls ${opendjCfgDir}/config/*.sh 2>/dev/null)"
for f in ${fileList}; do
    echo "#### Setting up custom prerequisite script: $f"
    source $f
done
echo

echo "#### Creating backends"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-backend.sh -n ${localHostName} ${instanceOpts}
echo

echo "#### Creating backend indexes"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-backend-index.sh -n ${localHostName} ${instanceOpts}
echo

echo "#### Creating Plugins"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-plugin.sh -n ${localHostName} ${instanceOpts}
echo

echo "#### Creating Log Publishers"
sudo -u "${ziAdmin}" ${OPENDJ_TOOLS_DIR}/bin/opendj-setup-log-publisher.sh -n ${localHostName} ${instanceOpts}
echo

if [ ! -z "${OPENDJ_GLOBAL_SMTP_SVR}" ]; then
    echo "#### Enabling global SMTP server: ${OPENDJ_GLOBAL_SMTP_SVR}"
    ${OPENDJ_HOME_DIR}/bin/dsconfig set-global-configuration-prop \
    --port ${OPENDJ_ADMIN_PORT}         \
    --hostname ${localHostName}         \
    --bindDN "${localDirMgrDN}"         \
    --bindPassword ${localDirMgrPasswd} \
    --set smtp-server:${OPENDJ_GLOBAL_SMTP_SVR} \
    -f -X -n
fi

if [ -z "${OPENDJ_LDAP_PORT}" ]; then
    echo "#### Removing unused protocol handler: LDAP"
    ${OPENDJ_HOME_DIR}/bin/dsconfig delete-connection-handler \
    --port ${OPENDJ_ADMIN_PORT}                 \
    --hostname ${localHostName}                 \
    --bindDN "${localDirMgrDN}"                 \
    --bindPassword ${localDirMgrPasswd}         \
    --handler-name "LDAP Connection Handler"    \
    -f -X -n
fi

if [ -z "${OPENDJ_LDAPS_PORT}" ]; then
    echo "#### Removing unused protocol handler: LDAPS"
    ${OPENDJ_HOME_DIR}/bin/dsconfig delete-connection-handler \
    --port ${OPENDJ_ADMIN_PORT}                 \
    --hostname ${localHostName}                 \
    --bindDN "${localDirMgrDN}"                 \
    --bindPassword ${localDirMgrPasswd}         \
    --handler-name "LDAPS Connection Handler"   \
    -f -X -n
fi

if [ -z "${OPENDJ_JMX_PORT}" ]; then
    echo "#### Removing unused protocol handler: JMX"
    ${OPENDJ_HOME_DIR}/bin/dsconfig delete-connection-handler \
    --port ${OPENDJ_ADMIN_PORT}                 \
    --hostname ${localHostName}                 \
    --bindDN "${localDirMgrDN}"                 \
    --bindPassword ${localDirMgrPasswd}         \
    --handler-name "JMX Connection Handler"     \
    -f -X -n
fi

echo "#### Restarting OpenDJ after reconfiguration"
${OPENDJ_TOOLS_DIR}/bin/opendj-ops-control.sh restartWait ${instanceRoot}

if [ ! -z "${OPENDJ_PSEARCH_GRP}" ]; then
echo "#### Adding global aci for persistent search"
    ${OPENDJ_HOME_DIR}/bin/dsconfig set-access-control-handler-prop \
        --port ${OPENDJ_ADMIN_PORT}         \
        --hostname ${localHostName}         \
        --bindDN "${localDirMgrDN}"         \
        --bindPassword ${localDirMgrPasswd} \
        -X -n                               \
        --add global-aci:"(targetcontrol=\"2.16.840.1.113730.3.4.3\") (version 3.0; acl \"Allow persistent search\"; allow (search, read) (groupdn = \"ldap:///${OPENDJ_PSEARCH_GRP}\");)"
fi

if [ ! -z "${OPENDJ_PSEARCH_USER}" ]; then
echo "#### Adding global aci for persistent search"
    ${OPENDJ_HOME_DIR}/bin/dsconfig set-access-control-handler-prop \
        --port ${OPENDJ_ADMIN_PORT}         \
        --hostname ${localHostName}         \
        --bindDN "${localDirMgrDN}"         \
        --bindPassword ${localDirMgrPasswd} \
        -X -n                               \
        --add global-aci:"(targetcontrol=\"2.16.840.1.113730.3.4.3\") (version 3.0; acl \"Allow persistent search\"; allow (search, read) (userdn = \"ldap:///${OPENDJ_PSEARCH_USER}\");)"
fi

if [ ! -z "${OPENDJ_MOD_SCHEMA_GRP}" ]; then
echo "#### Adding global aci for modify schema"
    ${OPENDJ_HOME_DIR}/bin/dsconfig set-access-control-handler-prop \
        --port ${OPENDJ_ADMIN_PORT}           \
        --hostname ${localHostName}           \
        --bindDN "${localDirMgrDN}"           \
        --bindPassword ${localDirMgrPasswd}   \
        -X -n                                 \
        --add global-aci:"(target = \"ldap:///cn=schema\")(targetattr = \"attributeTypes || objectClasses\")(version 3.0;acl \"Modify schema\"; allow (search, read, write) (groupdn = \"ldap:///${OPENDJ_MOD_SCHEMA_GRP}\");)"
fi

if [ ! -z "${OPENDJ_MOD_SCHEMA_USER}" ]; then
echo "#### Adding global aci for modify schema"
    ${OPENDJ_HOME_DIR}/bin/dsconfig set-access-control-handler-prop \
        --port ${OPENDJ_ADMIN_PORT}           \
        --hostname ${localHostName}           \
        --bindDN "${localDirMgrDN}"           \
        --bindPassword ${localDirMgrPasswd}   \
        -X -n                                 \
        --add global-aci:"(target = \"ldap:///cn=schema\")(targetattr = \"attributeTypes || objectClasses\")(version 3.0;acl \"Modify schema\"; allow (search, read, write) (userdn = \"ldap:///${OPENDJ_MOD_SCHEMA_USER}\");)"
fi

#     echo "#### Creating admin user"
# 	${OPENDJ_HOME_DIR}/bin/dsframework create-admin-user \
# 		--port ${OPENDJ_ADMIN_PORT}         \
# 		--hostname ${localHostName}         \
# 		--bindDN "${localDirMgrDN}"         \
# 		--bindPassword ${localDirMgrPasswd} \
# 		--userID admin                      \
# 		--set password:${localAdminPasswd}  \
# 		-X

echo "#### Listing Backends"
if [ -f "${OPENDJ_HOME_DIR}/bin/list-backends" ]; then
    sudo -u "${ziAdmin}" ${OPENDJ_HOME_DIR}/bin/list-backends
else
    sudo -u "${ziAdmin}"  ${OPENDJ_HOME_DIR}/bin/dsconfig list-backends \
    --port ${OPENDJ_ADMIN_PORT}         \
    --hostname ${localHostName}         \
    --bindDN "${localDirMgrDN}"         \
    --bindPassword ${localDirMgrPasswd} \
    --trustAll                          \
    --no-prompt
fi

echo "#### Finished setting up OpenDJ"

cd ${SAVE_DIR}
