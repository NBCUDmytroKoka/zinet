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
		echo "#### This script must be run as root."
		exit 0
fi

localConfigDir=
localDirMgrDN=
: ${instanceRoot=}
localTenantList=
localExtensionList=
localSecretsFile=

USAGE="	Usage: `basename $0` -c configDir -T localTenantList -D Directory Manager DN -Y Secrets File [ -I instanceRoot ] [ -e localExtensionList ]"

while getopts hc:D:Y:I:T:e: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        c)
            localConfigDir="$OPTARG"
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
        T)
            localTenantList="$OPTARG"            
            ;;
        e)
            localExtensionList="$OPTARG"            
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            cd ${SAVE_DIR}
            exit 1
            ;;
    esac
done

if [ -z "${localConfigDir}" ]; then
	echo "Must pass a valid config folder"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${localTenantList}" ]; then
	echo "Must pass a valid tenant list"
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
localDirMgrPasswd="${OPENDJ_DS_DIRMGRPASSWD}"
localAdminPasswd="${OPENDJ_ADM_PASSWD}"
localSvcAcctPasswd="${OPENDJ_SVC_PASSWD}"

if [ -z "${localDirMgrPasswd}" ]; then
	echo "Must pass a valid directory manager password"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

if [ -z "${localAdminPasswd}" ]; then
	echo "Must pass a valid admin password"
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

BACKOUT_DATE=$(date +%Y%m%d-%H%M%S)

echo "#### loading ziNet - $SCRIPT"
source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Error reading zinet default runtime"
	exit 1
fi

for f in ${ziNetEtcDir}/*.functions; do source $f; done 2> /dev/null
for f in ${ziNetEtcDir}/*.properties; do source $f; done 2> /dev/null

echo "#### Reading in config"
for f in ${SCRIPTPATH}/opendj-*-default.properties; do echo "#### Reading default config: $f"; source $f; done 2> /dev/null
for f in ${localConfigDir}/opendj-*-override.properties; do echo "#### Reading override config: $f"; source $f; done 2> /dev/null

echo "#### Setting up config directory: ${ziNetEtcDir}/opendj"
opendjCfgDir=${ziNetEtcDir}/opendj
if [ ! -z ${instanceRoot} ]; then
    opendjCfgDir="${opendjCfgDir}/${instanceRoot}"
fi

echo "#### preparing opendj directory"
if [ ! -d $(dirname ${OPENDJ_HOME_DIR}) ]; then
    mkdir -p $(dirname ${OPENDJ_HOME_DIR})
    chown ${OPENDJ_USER}:${OPENDJ_GRP} $(dirname ${OPENDJ_HOME_DIR})
fi

if [ ! -d $(dirname ${OPENDJ_TOOLS_DIR}) ]; then
    mkdir -p $(dirname ${OPENDJ_TOOLS_DIR})
    chown ${OPENDJ_USER}:${OPENDJ_GRP} $(dirname ${OPENDJ_TOOLS_DIR})
fi

if [ ! -d $(dirname ${OPENDJ_BACKUP_DIR}) ]; then
    mkdir -p $(dirname ${OPENDJ_BACKUP_DIR})
    chown ${OPENDJ_USER}:${OPENDJ_GRP} $(dirname ${OPENDJ_BACKUP_DIR})
fi

echo "#### creating tools location"
mkdir -p ${OPENDJ_TOOLS_DIR}/bin
mkdir -p ${OPENDJ_TOOLS_DIR}/share
chmod 750 ${OPENDJ_TOOLS_DIR}
chown ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_TOOLS_DIR}

echo "#### creating backups location"
mkdir -p ${OPENDJ_BACKUP_DIR}
chmod 750 ${OPENDJ_BACKUP_DIR}
chown ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_BACKUP_DIR}

echo "#### Applying Patches & Extensions"
if [ ! -z "${localExtensionList}" ]; then
    IFS=',' read -ra extArr <<< "${localExtensionList}"
    for updateFile in "${extArr[@]}"; do
        echo "#### Applying ${updateFile}"
        tmpDir=$(mktemp -d /tmp/."XXXXXXXXXXXXXXX")
        unzip ${updateFile} -d ${tmpDir}

        theFileName=$(basename ${updateFile})
        archiveBaseName=${theFileName%\.*}
        
        if [ -d "${tmpDir}/${archiveBaseName}" ]; then
            cp -r ${tmpDir}/*/* ${OPENDJ_HOME_DIR}/        
        else
            cp -r ${tmpDir}/* ${OPENDJ_HOME_DIR}/
        fi
        rm -rf ${tmpDir}
    done
fi
chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_HOME_DIR}

if [ ! -z "${OPENDJ_JAVA_ARGS}" ]; then
    sudo -u ${OPENDJ_USER} cp ${OPENDJ_HOME_DIR}/config/java.properties ${OPENDJ_HOME_DIR}/config/archived-configs/java.properties.${BACKOUT_DATE}
    sed -i "s|^[ \t]*\(start-ds.java-args\)[ \t]*=.*|\1=${OPENDJ_JAVA_ARGS}|g" ${OPENDJ_HOME_DIR}/config/java.properties
    [ -f ${OPENDJ_HOME_DIR}/bin/dsjavaproperties ] && ${OPENDJ_HOME_DIR}/bin/dsjavaproperties  
fi

echo "#### Setting up instance runtime"
echo "export PATH=\${PATH}:${opendjCfgDir}/bin:${OPENDJ_HOME_DIR}/bin" > ${opendjCfgDir}/.bashrc
echo 'alias ll="ls -al"' >> ${opendjCfgDir}/.bashrc
echo "complete -W \"$(${OPENDJ_HOME_DIR}/bin/dsconfig --help-all|grep '^[a-z].*' | tr '\n' ' ')\" dsconfig" >> ${opendjCfgDir}/.bashrc
echo "complete -W \"$(${OPENDJ_HOME_DIR}/bin/dsreplication --help|grep -v -e '^data' -e '^enable' -e '^contents'|grep '^[a-z].*' | tr '\n' ' ')\" dsreplication" >> ${opendjCfgDir}/.bashrc
chmod 640 ${opendjCfgDir}/.bashrc

echo "#### Setting up global runtime"
LDAPTLS_CACERT=$(find "${ziNetEtcDir}/pki/server" -name "*-cachain.crt" 2>/dev/null | head -1)
echo "export LDAPTLS_CACERT=${LDAPTLS_CACERT}" > /etc/profile.d/opendj.sh
echo "export PATH=\${PATH}:${OPENDJ_TOOLS_DIR}/bin" >> /etc/profile.d/opendj.sh
chmod 644 /etc/profile.d/opendj.sh

echo "#### Setting up OpenDJ user environment"
# copy standard properties files, then copy any user-defined custom ones
/bin/cp -f ${SCRIPTPATH}/opendj-*-default.properties ${opendjCfgDir}/
chmod 640 ${opendjCfgDir}/opendj-*-default.properties

/bin/cp -f ${SCRIPTPATH}/*.functions ${opendjCfgDir}/
chmod 640 ${opendjCfgDir}/*.functions

/bin/cp -f ${localConfigDir}/opendj-*-override.properties ${opendjCfgDir}/ 2> /dev/null
chmod 640 ${opendjCfgDir}/opendj-*-override.properties 2> /dev/null

echo "#### Setting up service account file"
cat <<- EOF > ${opendjCfgDir}/.netrc
machine OpenDJ_Root
    login ${localDirMgrDN}
    password ${localDirMgrPasswd}

machine OpenDJ_Admin
    login admin
    password ${localAdminPasswd}

$([ -n "${OPENDJ_SVCS_OPS_DN}" ] && echo machine OpenDJ_Service)
$([ -n "${OPENDJ_SVCS_OPS_DN}" ] && echo     login uid=service_opendj,${OPENDJ_SVCS_OPS_DN})
$([ -n "${OPENDJ_SVCS_OPS_DN}" ] && echo     password ${localSvcAcctPasswd})
EOF
chmod 640 ${opendjCfgDir}/.netrc

echo "#### Copying scripts and templates"
mkdir -p ${opendjCfgDir}/bin
cp -f ${SCRIPTPATH}../shell/* ${opendjCfgDir}/bin/
chmod 750 ${opendjCfgDir}/bin/*

cp -f ${SCRIPTPATH}/opendj-*.sh ${OPENDJ_TOOLS_DIR}/bin/
chmod 750 ${OPENDJ_TOOLS_DIR}/bin/opendj-*.sh

cp -rf ${SCRIPTPATH}/../dsconfig ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig 2>/dev/null
chmod 640 ${OPENDJ_TOOLS_DIR}/share/opendj-standard-dsconfig/*

cp -rf ${SCRIPTPATH}/../mail-templates ${OPENDJ_TOOLS_DIR}/share/opendj-mail-templates 2>/dev/null
chmod 640 ${OPENDJ_TOOLS_DIR}/share/opendj-mail-templates/*

cp -rf ${SCRIPTPATH}/../policies ${OPENDJ_TOOLS_DIR}/share/opendj-policies 2>/dev/null
chmod 640 ${OPENDJ_TOOLS_DIR}/share/opendj-policies/*

mkdir -p ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif
cp -rf ${SCRIPTPATH}/../ldif/*-tenants-*.ldif ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif/ 2>/dev/null
chmod 640 ${OPENDJ_TOOLS_DIR}/share/opendj-standard-ldif/*
chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_TOOLS_DIR}

if [ -d "${localConfigDir}/custom-mail-templates" ]; then
    cp -rf ${localConfigDir}/custom-mail-templates ${opendjCfgDir}/mail-templates 2>/dev/null
else
    mkdir ${opendjCfgDir}/mail-templates
fi
chmod 640 ${opendjCfgDir}/mail-templates/* 2>/dev/null

if [ -d "${localConfigDir}/custom-policies" ]; then
    cp -rf ${localConfigDir}/custom-policies ${opendjCfgDir}/policies 2>/dev/null
else
    mkdir ${opendjCfgDir}/policies
fi
chmod 640 ${opendjCfgDir}/policies/* 2>/dev/null

if [ -d "${localConfigDir}/custom-schema" ]; then
    cp -rf ${localConfigDir}/custom-schema ${opendjCfgDir}/schema 2>/dev/null
else
    mkdir ${opendjCfgDir}/schema
fi
chmod 640 ${opendjCfgDir}/schema/* 2>/dev/null

if [ -d "${localConfigDir}/custom-config" ]; then
    cp -rf ${localConfigDir}/custom-config ${opendjCfgDir}/config 2>/dev/null
else
    mkdir ${opendjCfgDir}/config
fi
chmod 640 ${opendjCfgDir}/config/* 2>/dev/null

echo "#### Setting OpenDJ config dir permissions"
chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${opendjCfgDir}

IFS=' ' read -ra theTenants  <<< "${localTenantList}"
for localTenantId in "${theTenants[@]}"; do
    echo "#### Installing SMTP Templates for tenant: ${localTenantId}"
    mkdir -p ${OPENDJ_HOME_DIR}/config/${localTenantId}

    for f in $(ls ${OPENDJ_TOOLS_DIR}/share/opendj-mail-templates/*.template 2>/dev/null); do
        echo "#### Expanding standard mail template: ${f} for tenant: ${localTenantId}"
        theFileName=$(basename $f)
        apply_shell_expansion ${f} > ${OPENDJ_HOME_DIR}/config/${localTenantId}/${theFileName}
    done

    for f in $(ls ${opendjCfgDir}/mail-templates/*.template 2>/dev/null); do
        echo "#### Expanding custom mail template: ${f} for tenant: ${localTenantId}"
        theFileName=$(basename $f)
        apply_shell_expansion ${f} > ${OPENDJ_HOME_DIR}/config/${localTenantId}/${theFileName}
    done

    echo "#### Installing Dictionaries for tenant: ${localTenantId}"
    /bin/cp -r ${OPENDJ_TOOLS_DIR}/share/opendj-standard-policies/*.dict ${OPENDJ_HOME_DIR}/config/${localTenantId}/ 2>/dev/null
    if [ -d ${opendjCfgDir}/policies ]; then
        /bin/cp ${opendjCfgDir}/policies/*.dict ${OPENDJ_HOME_DIR}/config/${localTenantId}/ 2> /dev/null
    fi
    chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_HOME_DIR}/config/${localTenantId}
done