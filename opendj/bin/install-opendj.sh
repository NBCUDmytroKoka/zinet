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

subjectName=$(hostname)
localConfigDir=
opendjZipArchive=
localDirMgrDN=
localNodeTemplate=node-template.config
: ${instanceRoot=}
localTenantList=
localExtensionList=
localSecretsFile=

USAGE="	Usage: `basename $0` -c configDir -T localTenantList -z OpenDJ zip file -D Directory Manager DN -Y Secrets File [ -I instanceRoot ] [ -t nodeTemplateConfig ] [-s subjectName=$(hostname)] [ -e localExtensionList ]"

while getopts hc:z:D:Y:t:s:I:T:e: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        c)
            localConfigDir="$OPTARG"
            ;;
        z)
            opendjZipArchive="$OPTARG"
            ;;
        D)
            localDirMgrDN="$OPTARG"
            ;;
        Y)
            localSecretsFile="$OPTARG"
            ;;
        t)
            localNodeTemplate="$OPTARG"
            ;;
        s)
            subjectName="$OPTARG"
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

# if [[ $(id -un) != "${OPENDJ_USER}" ]]; then
# 		echo "This script must be run as ${OPENDJ_USER}."
# 		exit 1
# fi

echo "#### Setting up config directory: ${ziNetEtcDir}/opendj"
opendjCfgDir=${ziNetEtcDir}/opendj
mkdir -p ${opendjCfgDir}

userCreated=false
if [ -z "$(getent passwd ${OPENDJ_USER} 2>/dev/null)" ]; then
    echo "#### Adding opendj user: ${OPENDJ_USER}"
    [ -z "$(getent group ${OPENDJ_GROUP} 2>/dev/null)" ] && groupadd ${OPENDJ_GROUP}
    useradd -s /bin/false -g ${OPENDJ_GROUP} -d ${opendjCfgDir} ${OPENDJ_USER}
    userCreated=true
fi

if [ ! -z ${instanceRoot} ]; then
    echo "#### Relocating instance to: ${opendjCfgDir}/${instanceRoot}"
    opendjCfgDir="${opendjCfgDir}/${instanceRoot}"
    mkdir -p ${opendjCfgDir}
    if $userCreated; then
        usermod -d ${opendjCfgDir} ${OPENDJ_USER}
    fi
fi

chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${opendjCfgDir}

userInGroup=$(getent group ${OPENDJ_GRP} 2>/dev/null | grep ${OPENDJ_USER} && echo true || echo false)
if [[ $userInGroup == false ]]; then
    echo "#### granting OPENDJ_USER permission to existing OPENDJ_USER"
    usermod -a -G ${OPENDJ_GRP} ${OPENDJ_USER}
fi

if [ "${ziAdmin}" != "${OPENDJ_USER}" ]; then
    userInGroup=$(getent group ${OPENDJ_GRP} 2>/dev/null | grep ${ziAdmin} && echo true || echo false)
    if [[ $userInGroup == false ]]; then
        echo "#### granting OPENDJ_GRP permission to ziAdmin"
        usermod -a -G ${OPENDJ_GRP} ${ziAdmin}
    fi
fi

echo "#### Configuring file limits"
cat > /etc/security/limits.d/80-${OPENDJ_USER}.conf <<EOF
${OPENDJ_USER} soft nofile 65536
${OPENDJ_USER} hard nofile 131072
EOF
sysctl -p >/dev/null

if [ "${OPENDJ_FIREWALL_ENABLED}" == "true" ]; then
    echo "#### Configuring iptables"
    [ ! -z "${OPENDJ_LDAP_PORT}" ] && ufw allow ${OPENDJ_LDAP_PORT}/tcp
    [ ! -z "${OPENDJ_LDAPS_PORT}" ] && ufw allow ${OPENDJ_LDAPS_PORT}/tcp
    [ ! -z "${OPENDJ_ADMIN_PORT}" ] && ufw allow ${OPENDJ_ADMIN_PORT}/tcp
    [ ! -z "${OPENDJ_JMX_PORT}" ] && ufw allow ${OPENDJ_JMX_PORT}/tcp
    ufw default deny

    iptables -P INPUT ACCEPT
    iptables -F
    iptables -A INPUT -i lo                                 -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED  -j ACCEPT
    iptables -A INPUT -p tcp --dport 22                     -j ACCEPT
    [ ! -z "${OPENDJ_LDAP_PORT}" ] && iptables -A INPUT -p tcp --dport ${OPENDJ_LDAP_PORT}    -j ACCEPT
    [ ! -z "${OPENDJ_LDAPS_PORT}" ] && iptables -A INPUT -p tcp --dport ${OPENDJ_LDAPS_PORT}   -j ACCEPT
    [ ! -z "${OPENDJ_ADMIN_PORT}" ] &&  iptables -A INPUT -p tcp --dport ${OPENDJ_ADMIN_PORT}   -j ACCEPT
    [ ! -z "${OPENDJ_JMX_PORT}" ] &&  iptables -A INPUT -p tcp --dport ${OPENDJ_JMX_PORT}     -j ACCEPT
    iptables -P INPUT DROP
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD DROP

    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

    $(which apt-get) && apt-get install -y iptables-persistent || yum install -y iptables-persistent
fi

echo "#### installing dependencies dist"

haveApt=$(which apt-get 2>/dev/null)

if [ ! -z "${haveApt}" ]; then
    echo "#### updating OS packages - apt"
    apt-get update -y && apt-get upgrade -y
else
    echo "#### updating OS packages - yum"
    yum update -y && yum upgrade -y
fi
 
needInstall=$(which unzip 2>/dev/null)
if [ -z "${needInstall}" ]; then
    [ ! -z "${haveApt}" ] && apt-get install -y unzip || yum install -y unzip
fi

needInstall=$(which ldapsearch 2>/dev/null)
if [ -z "${needInstall}" ]; then
    [ ! -z "${haveApt}" ] && apt-get install -y ldap-utils || yum install -y openldap-clients
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

echo "#### Expanding OpenDJ dist"
if [ -n ${opendjZipArchive} ]; then
    if [ ! -d ${OPENDJ_HOME_DIR} ]; then
        # we are passed an opendj archive AND the opendj directory doesn't exist already
        tmpODJ=$(mktemp -d /tmp/."XXXXXXXXXXXXXXX")
        unzip ${opendjZipArchive} -d ${tmpODJ}
        mv ${tmpODJ}/opendj/* ${OPENDJ_HOME_DIR}/
        rm -rf ${tmpODJ}
    fi
else
    if [ ! -d ${OPENDJ_HOME_DIR} ]; then
        echo "The OpenDJ zip archive was not found and the OpenDJ home directory doesn't exist."
        cd ${SAVE_DIR}
        exit 1
    else
        echo "Using existing OpenDj binary installation."
    fi
fi
chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_HOME_DIR}

echo "#### Applying configuration template"
templateFile=
if [ -f "${localConfigDir}/${localNodeTemplate}" ]; then
    templateFile="${localConfigDir}/${localNodeTemplate}"
elif [ -f "${SCRIPTPATH}/${localNodeTemplate}" ]; then
    templateFile="${SCRIPTPATH}/${localNodeTemplate}"
else
    echo "#### Can't find the specified template: ${localNodeTemplate}. Defaulting to ${SCRIPTPATH}/node-template.config"
    exit 1
fi

if [ ! -z "${OPENDJ_INSTANCE_LOCATION}" ]; then
    echo "#### Setting up instance location @ ${OPENDJ_INSTANCE_LOCATION}"
    mkdir -p "${OPENDJ_INSTANCE_LOCATION}"
    chmod 750 ${OPENDJ_INSTANCE_LOCATION}
    ln -sf ${OPENDJ_INSTANCE_LOCATION} ${OPENDJ_HOME_DIR}/data
    ln -sf ${OPENDJ_INSTANCE_LOCATION}/config ${OPENDJ_HOME_DIR}/config
    ln -sf ${OPENDJ_INSTANCE_LOCATION}/logs ${OPENDJ_HOME_DIR}/logs
    chown ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_HOME_DIR}/{data,config,logs} >/dev/null 2>&1
fi

if [ -f ${OPENDJ_HOME_DIR}/bin/dsjavaproperties ]; then
    echo "#### Preparing to run the setup for DJ 2.6x - 3.5x"
    tmpSetup=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
    apply_shell_expansion "${templateFile}" | sudo -u ${OPENDJ_USER} tee ${tmpSetup}
    chmod 440 ${tmpSetup}
    sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/setup ${OPENDJ_SERVER_TYPE} --cli --propertiesFilePath ${tmpSetup} --acceptLicense --no-prompt
    rm -f ${tmpSetup}
else
    echo "#### Preparing to run the setup for DJ 5.x"
    tmpSetup=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
    echo -n "sudo -u ${OPENDJ_USER} ${OPENDJ_HOME_DIR}/setup " > ${tmpSetup}
    apply_shell_expansion "${templateFile}" | grep -v "^#" >> ${tmpSetup}
    chmod 440 ${tmpSetup}
    source ${tmpSetup}
    rm -f ${tmpSetup}
fi

mkdir -p ${OPENDJ_HOME_DIR}/config/archived-configs
chmod 755 ${OPENDJ_HOME_DIR}/config/archived-configs

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
[ ! -z "${OPENDJ_INSTANCE_LOCATION}" ] && chown -R ${OPENDJ_USER}:${OPENDJ_GRP} ${OPENDJ_INSTANCE_LOCATION}

echo "#### Configuring OpenDJ configuration objects"
sudo -u ${OPENDJ_USER} cp ${OPENDJ_HOME_DIR}/config/config.ldif ${OPENDJ_HOME_DIR}/config/archived-configs/config.ldif.${BACKOUT_DATE}
sed -i "s|^ds-cfg-single-structural-objectclass-behavior.*|ds-cfg-single-structural-objectclass-behavior: accept|" ${OPENDJ_HOME_DIR}/config/config.ldif
# sed -i "s|^ds-cfg-reject-unauthenticated-requests.*|ds-cfg-reject-unauthenticated-requests: true|" ${OPENDJ_HOME_DIR}/config/config.ldif

if [ ! -z "${OPENDJ_ALIAS}" ]; then
    sed -i "/ds-cfg-alternate-bind-dn/a ds-cfg-alternate-bind-dn: ${OPENDJ_ALIAS}" ${OPENDJ_HOME_DIR}/config/config.ldif
fi

if [ ! -z "${OPENDJ_JAVA_ARGS}" ]; then
    sudo -u ${OPENDJ_USER} cp ${OPENDJ_HOME_DIR}/config/java.properties ${OPENDJ_HOME_DIR}/config/archived-configs/java.properties.${BACKOUT_DATE}
    sed -i "s|^[ \t]*\(start-ds.java-args\)[ \t]*=.*|\1=${OPENDJ_JAVA_ARGS}|g" ${OPENDJ_HOME_DIR}/config/java.properties
    sed -i "s|^[ \t]*\(ldapmodify.java-args\)[ \t]*=.*|\1=-Xms256m -client|g" ${OPENDJ_HOME_DIR}/config/java.properties
    sed -i "s|^[ \t]*\(ldapsearch.java-args\)[ \t]*=.*|\1=-Xms256m -client|g" ${OPENDJ_HOME_DIR}/config/java.properties
    echo "overwrite-env-java-args=true" >> ${OPENDJ_HOME_DIR}/config/java.properties
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

touch ${opendjCfgDir}/.netrc
chmod 640 ${opendjCfgDir}/.netrc

echo "#### Setting up service account file"
echo "machine OpenDJ_Root" >> ${opendjCfgDir}/.netrc
echo "    login ${localDirMgrDN}" >> ${opendjCfgDir}/.netrc
echo "    password ${localDirMgrPasswd}" >> ${opendjCfgDir}/.netrc
echo >> ${opendjCfgDir}/.netrc
echo "machine OpenDJ_Admin" >> ${opendjCfgDir}/.netrc
echo "    login admin" >> ${opendjCfgDir}/.netrc
echo "    password ${localAdminPasswd}" >> ${opendjCfgDir}/.netrc
if [ ! -z "${OPENDJ_SVCS_OPS_DN}" ]; then
    echo >> ${opendjCfgDir}/.netrc
    echo "machine OpenDJ_Service" >> ${opendjCfgDir}/.netrc
    echo "    login uid=service_opendj,${OPENDJ_SVCS_OPS_DN}" >> ${opendjCfgDir}/.netrc
    echo "    password ${localSvcAcctPasswd}" >> ${opendjCfgDir}/.netrc
fi

echo "#### Copying scripts and templates"
mkdir -p ${opendjCfgDir}/bin
cp -f ${SCRIPTPATH}/../shell/* ${opendjCfgDir}/bin/
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


echo "#### Setting up opendj system service"
serviceName=opendj
if [ ! -z "${OPENDJ_SCV_NAME}" ]; then
    serviceName="${OPENDJ_SCV_NAME}"
elif [ ! -z "${instanceRoot}" ]; then
    serviceName="${instanceRoot}"
fi

echo "#### Starting OpenDJ"
echo "#### Creating opendj service"
if [ "$(pidof systemd)" ]; then

    if [ -f /etc/profile.d/java.sh ]; then
        source /etc/profile.d/java.sh
        OPENDJ_JAVA_HOME=${JAVA_HOME}
    else
        javaBin=$(readlink -f $(which java))
        if [ -z "${javaBin}" ]; then
            echo "#### Can't find a JVM to run OpenDJ"
            exit 1    
        fi
        OPENDJ_JAVA_HOME=$(dirname ${javaBin})
    fi

    echo "#### Installing systemd service"
    if [ -f "${localConfigDir}/${OPENDJ_SVC_TMPL}" ]; then
        apply_shell_expansion "${localConfigDir}/${OPENDJ_SVC_TMPL}" >  ${opendjCfgDir}/${serviceName}.service
    else
        apply_shell_expansion "${SCRIPTPATH}/${OPENDJ_SVC_TMPL}" > ${opendjCfgDir}/${serviceName}.service
    fi
    chmod 750 ${opendjCfgDir}/${serviceName}.service
    chown ${OPENDJ_USER}:${OPENDJ_GRP} ${opendjCfgDir}/${serviceName}.service

    cp -f ${opendjCfgDir}/${serviceName}.service /etc/systemd/system/${serviceName}.service
    systemctl daemon-reload
    systemctl enable ${serviceName}.service
    systemctl start ${serviceName}.service

    echo
    echo "#### System Status"
    systemctl -l status ${serviceName}.service
    echo
else
    echo "#### Installing SysV service"

    ${OPENDJ_HOME_DIR}/bin/create-rc-script --outputFile ${opendjCfgDir}/${serviceName}.init --userName ${OPENDJ_USER} --javaHome "${OPENDJ_JAVA_HOME}" --javaArgs $"{OPENDJ_JAVA_ARGS}"
    chmod 750 ${opendjCfgDir}/${serviceName}.init
    chown ${OPENDJ_USER}:${OPENDJ_GRP} ${opendjCfgDir}/${serviceName}.init

    ln -sf ${opendjCfgDir}/${serviceName}.init /etc/init.d/${serviceName}
    chkconfig --add /etc/init.d/${serviceName}
    chkconfig ${serviceName} on
    service ${serviceName} start
fi
