#!/usr/bin/env bash

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

localRepoFolder=
localInventoryFile=
localSecretsFile=
localUserAccount=
localSkipRepoSync=false

USAGE="	Usage: `basename $0` -i localInventoryFile [ -r localRepoFolder ] [ -Y localSecretsFile ] [ -u localUserAccount ] [ -s localSkipRepoSync=false ]"

while getopts hi:r:Y:u:s OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        i)
            localInventoryFile="$OPTARG"
            ;;
        r)
            localRepoFolder="$OPTARG"
            ;;
        Y)
            localSecretsFile="$OPTARG"
            ;;
        u)
            localUserAccount="$OPTARG"
            ;;
        s)
            localSkipRepoSync=true
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

if [ ! -f "${localInventoryFile}" ]; then
	echo "#### Must pass a valid inventory file"
    echo $USAGE >&2
	exit 1
fi

if [ -f "${localSecretsFile}" ]; then
    echo "#### loading in secrets"
    source "${localSecretsFile}"
    if [ $? -ne 0 ]; then
        echo "#### error loading secrets file"
        echo $USAGE >&2
        exit 1
	fi
fi

userSSHOpts=
remoteUserPasswd=
if [ ! -z "${localUserAccount}" ]; then
    remoteUserPasswd=$(grep -w "${localUserAccount}" "${localSecretsFile}"| awk -F= '{ print $2 }')
    userSSHOpts="${localUserAccount}@"
fi

################################################
#
#	Functions
#
################################################

getPassword()
{
    while [ -z "$PASSWORD" ]
    do
        echo "Please enter the ${1} password:" >&2
        read -s PASSWORD1
        echo "Please re-enter the password to confirm:" >&2
        read -s PASSWORD2

        if [ "$PASSWORD1" = "$PASSWORD2" ]; then
            PASSWORD=$PASSWORD1
        else
            # Output error message in red
            red='\033[0;31m'
            NC='\033[0m' # No Color
            echo -e "\n${red}Passwords did not match!${NC}" >&2
        fi
    done
    echo "$PASSWORD"
}

copyPasswordFile() {
    local outFileName="${1}"
    local -n inputArray="${2}"
    local secretFile="${3}"
    
    cat "${secretFile}" > "${outFileName}"
    chmod 400 "${outFileName}"
}

createPasswordFile() {
    local outFileName="${1}"
    local -n inputArray="${2}"
    local secretFile="${3}"

    for entryKey in "${!inputArray[@]}"; do
        entryDesc="${inputArray[$entryKey]}"

        # first check the secret file.
        if [ -z "${secretFile}" ]; then
            thePassword=$(getPassword "${entryDesc}")
        else
            thePassword=$(grep -w "${entryKey}" "${secretFile}"| awk -F= '{ print $2 }')
        fi

        if [ ! -z "${thePassword}" ]; then
            echo "${entryKey}=${thePassword}" >> "${outFileName}"
        fi
    done

    if [ -f "${outFileName}" ]; then
        chmod 400 "${outFileName}"
    fi
}

exitOnErr() {
    if [ "${1}" -ne 0 ]; then
      echo "#### Error executing ${2}"
      exit 1
    fi
}

SSH() {

    if [ ! -z "${remoteUserPasswd}" ]; then
        sshpass -p ${remoteUserPasswd} /usr/bin/ssh -oStrictHostKeyChecking=no $@
    else
        ssh -A -oStrictHostKeyChecking=no $@
    fi

}

SCP() {

    if [ ! -z "${remoteUserPasswd}" ]; then
        sshpass -p ${remoteUserPasswd} /usr/bin/scp -oStrictHostKeyChecking=no $@
    else
        scp $@
    fi

}

intializeServerSettings() {

    INSTALL_ZINET=false
    ZINET_TARGET_HOSTNAME=
    ZINET_STORAGE_DEV=
    ZINET_DATA_DIR=
    ZINET_ADMIN=
    ZINET_ADMIN_GRP=
    ZINET_ETCD_DIR=

    INSTALL_JAVA=false
    JAVA_REPO_FILENAME=
    JAVA_INSTALL_PKG=
    JAVA_ROOT_LOCATION=

    INSTALL_CA=false
    
    INSTALL_SSHLDAP=false
    
    INSTALL_NGINX=false
    
    INSTALL_FAIL2BAN=false
    INSTALL_TOMCAT=false
    TOMCAT_CONFIG_DIR=
    TOMCAT_INSTALL_PKG=
    TOMCAT_TAR_FILENAME=

    INSTALL_OPENAM=false
    OPENAM_CONFIG_DIR=
    OPENAM_NODE_TEMPLATE=
    OPENAM_UPDATE_LIST=
    OPENAM_ZIP_ARCHIVE=
    OPENAM_KEYSTORE_SEED_SVR=false
    OPENAM_NEED_SEED=true
    OPENAM_DEPLOY_CONFIG=false
    UPDATEER_OPENAM_APPLY_PATCHES=false
    OPENDJ_OPS_MAINT=
    OPENDJ_OPS_MAINT_POLICY=
    
    SSHLDAP_FABRIC_HOST_ID=
    SSHLDAP_FABRIC_LAYERS=
    SSHLDAP_FABRIC_ROLES=
    SSHLDAP_FABRIC_SUDOERS=
    SSHLDAP_TENANT_ID=

    INSTALL_PKI=false
    PKI_GENERATE_EXTCA_REQ=false
    PKI_DEPLOY_EXTCA_CERT=false
    PKI_CERT_SUBJECT_ALIASES=
    PKI_CERT_SUBJECTNAME=
    PKI_ADMIN=
    PKI_ADMIN_GRP=
    PKI_KEYPIN_ID=
    PKI_KEYSTORE_ID=
    PKI_TRUSTSTORE_ID=
    UPDATER_PKI_JREJKS=false

    INSTALL_OPENDJ=false
    OPENDJ_ZIP_ARCHIVE=
    OPENDJ_CERT_SUBJECTNAME=
    OPENDJ_NODE_TEMPLATE=
    OPENDJ_INSTANCE_ID=
    OPENDJ_EXTENSIONS=
    OPENDJ_INSTANCE_CFG_DIR=

    REPLICATE_OPENDJ=false
    DEPLOY_SSHLDAP=false
    DEPLOY_TENANT=false
    DEPLOY_TENANT_ID=
    DEPLOY_POLICY_ID=
    DEPLOY_DOCKER=false
    
    INSTALL_DOCKER=false
}

printServerSettings() {

    echo "#### INSTALL_ZINET=${INSTALL_ZINET}"
    echo "#### ZINET_TARGET_HOSTNAME=${ZINET_TARGET_HOSTNAME}"
    echo "#### ZINET_ADMIN=${ZINET_ADMIN}"
    echo "#### ZINET_ADMIN_GRP=${ZINET_ADMIN_GRP}"
    echo "#### ZINET_STORAGE_DEV=${ZINET_STORAGE_DEV}"
    echo "#### ZINET_ETCD_DIR=${ZINET_ETCD_DIR}"
    echo "#### ZINET_DATA_DIR=${ZINET_DATA_DIR}"
    
    echo "#### INSTALL_JAVA=${INSTALL_JAVA}"
    echo "#### JAVA_REPO_FILENAME=${JAVA_REPO_FILENAME}"
    echo "#### JAVA_INSTALL_PKG=${JAVA_INSTALL_PKG}"
    echo "#### JAVA_ROOT_LOCATION=${JAVA_ROOT_LOCATION}"
    
    echo "#### INSTALL_CA=${INSTALL_CA}"
    
    echo "#### INSTALL_SSHLDAP=${INSTALL_SSHLDAP}"
    echo "#### SSHLDAP_FABRIC_HOST_ID=${SSHLDAP_FABRIC_HOST_ID}"
    echo "#### SSHLDAP_FABRIC_LAYERS=${SSHLDAP_FABRIC_LAYERS}"
    echo "#### SSHLDAP_FABRIC_ROLES=${SSHLDAP_FABRIC_ROLES}"
    echo "#### SSHLDAP_FABRIC_SUDOERS=${SSHLDAP_FABRIC_SUDOERS}"
    echo "#### SSHLDAP_TENANT_ID=${SSHLDAP_TENANT_ID}"
    
    echo "#### INSTALL_PKI=${INSTALL_PKI}"
    echo "#### PKI_GENERATE_EXTCA_REQ=${PKI_GENERATE_EXTCA_REQ}"
    echo "#### PKI_DEPLOY_EXTCA_CERT=${PKI_DEPLOY_EXTCA_CERT}"
    echo "#### PKI_CERT_SUBJECT_ALIASES=${PKI_CERT_SUBJECT_ALIASES}"
    echo "#### PKI_CERT_SUBJECTNAME=${PKI_CERT_SUBJECTNAME}"
    echo "#### PKI_ADMIN=${PKI_ADMIN}"
    echo "#### PKI_ADMIN_GRP=${PKI_ADMIN_GRP}"
    echo "#### PKI_KEYPIN_ID=${PKI_KEYPIN_ID}"
    echo "#### PKI_KEYSTORE_ID=${PKI_KEYSTORE_ID}"
    echo "#### PKI_TRUSTSTORE_ID=${PKI_TRUSTSTORE_ID}"
    echo "#### UPDATER_PKI_JREJKS=${UPDATER_PKI_JREJKS}"
    
    echo "#### INSTALL_OPENDJ=${INSTALL_OPENDJ}"
    echo "#### OPENDJ_ZIP_ARCHIVE=${OPENDJ_ZIP_ARCHIVE}"
    echo "#### OPENDJ_CERT_SUBJECTNAME=${OPENDJ_CERT_SUBJECTNAME}"
    echo "#### OPENDJ_NODE_TEMPLATE=${OPENDJ_NODE_TEMPLATE}"
    echo "#### OPENDJ_INSTANCE_ID=${OPENDJ_INSTANCE_ID}"
    echo "#### OPENDJ_EXTENSIONS=${OPENDJ_EXTENSIONS}"
    echo "#### OPENDJ_INSTANCE_CFG_DIR=${OPENDJ_INSTANCE_CFG_DIR}"
    echo "#### REPLICATE_OPENDJ=${REPLICATE_OPENDJ}"
    echo "#### DEPLOY_SSHLDAP=${DEPLOY_SSHLDAP}"
    echo "#### DEPLOY_TENANT=${DEPLOY_TENANT}"
    echo "#### DEPLOY_TENANT_ID=${DEPLOY_TENANT_ID}"
    echo "#### DEPLOY_POLICY_ID=${DEPLOY_POLICY_ID}"
    
    echo "#### INSTALL_DOCKER=${INSTALL_DOCKER}"
    echo "#### DEPLOY_DOCKER=${DEPLOY_DOCKER}"

    echo "#### INSTALL_NGINX=${INSTALL_NGINX}"

    echo "#### INSTALL_FAIL2BAN=${INSTALL_FAIL2BAN}"

    echo "#### INSTALL_TOMCAT=${INSTALL_TOMCAT}"
    echo "#### TOMCAT_CONFIG_DIR=${TOMCAT_CONFIG_DIR}"
    echo "#### TOMCAT_INSTALL_PKG=${TOMCAT_INSTALL_PKG}"
    echo "#### TOMCAT_TAR_FILENAME=${TOMCAT_TAR_FILENAME}"

    echo "#### INSTALL_OPENAM=${INSTALL_OPENAM}"
    echo "#### OPENAM_CONFIG_DIR=${OPENAM_CONFIG_DIR}"
    echo "#### OPENAM_NODE_TEMPLATE=${OPENAM_NODE_TEMPLATE}"
    echo "#### OPENAM_UPDATE_LIST=${OPENAM_UPDATE_LIST}"
    echo "#### OPENAM_ZIP_ARCHIVE=${OPENAM_ZIP_ARCHIVE}"
    echo "#### OPENAM_KEYSTORE_SEED_SVR=${OPENAM_KEYSTORE_SEED_SVR}"
    echo "#### OPENAM_NEED_SEED=${OPENAM_NEED_SEED}"
    echo "#### OPENAM_DEPLOY_CONFIG=${OPENAM_DEPLOY_CONFIG}"
    echo "#### UPDATEER_OPENAM_APPLY_PATCHES=${UPDATEER_OPENAM_APPLY_PATCHES}"
    echo "#### OPENDJ_OPS_MAINT=${OPENDJ_OPS_MAINT}"
    echo "#### OPENDJ_OPS_MAINT_POLICY=${OPENDJ_OPS_MAINT_POLICY}"

    echo
}

################################################
#
#	Main program
#
################################################

echo "#### Loading prerequisites"
if [ ! -f ini_parser.functions ]; then
    git archive --remote=git@bitbucket.org:zibernetics/zinet.git HEAD:common/bin ini_parser.functions | tar -x
fi

source ini_parser.functions
if [ $? -ne 0 ]; then
	echo "#### Can not load ini_parser.functions"
	exit 1
fi


####### Global variables
ziD=
ziNetEtcDir=
ziTenantId=
gCaHostName=
gExternalCA=false
gRepoKeyScan=
gDirMgrDN="cn=Directory Manager"
gSearchDomains=
gziAdmin=
gziAdminGrp=
gFetchRepoMode=git
gZinetRepoTar=
gZinetRepoDir=
gZinetCertDir=
gZinetConfigDir=
gHaveSudo=true
gRemoteBuildDir=/tmp/zinet-build
gPKIExtCaRootName=
gPKIExtCaSignName=
gOpenAMAppKeystore=keystore.jceks

declare -A opendjPasswds=(
    [OPENDJ_DS_DIRMGRPASSWD]="OpenDJ Directory Manager"
    [OPENDJ_ADM_PASSWD]="OpenDJ Directory Admin"
    [OPENDJ_SVC_PASSWD]="OpenDJ Service Acct" )

declare -A tomcatPasswds=(
    [TOMCAT_ROOT_PASSWD]="Tomcat Root")

declare -A sshPasswds=(
    [SSHLDAP_SVC_PASSWD]="SSHLDAP Service Acct")

declare -A dockerPasswds=(
    [DOCKER_SVC_PASSWD]="Docker Service Acct")

declare -A openamPasswds=(
    [OPENDJ_DS_DIRMGRPASSWD]="OpenDJ Directory Manager (Server Default)"
    [OPENDJ_DS_DIRMGRPASSWD_CFG]="OpenDJ Directory Manager (CFG)"
    [OPENDJ_DS_DIRMGRPASSWD_USR]="OpenDJ Directory Manager (USR)"
    [OPENDJ_DS_DIRMGRPASSWD_CTS]="OpenDJ Directory Manager (CTS)"
    [OPENAM_SVC_PASSWD]="OpenAM Service Acct"
    [OPENAM_ADMIN_PASSWD]="OpenAM amAdmin"
    [OPENAM_AGENT_PASSWD]="OpenAM amAgent" 
    [OPENAM_KEY_ID]="OpenAM PKI Key"
    [OPENAM_KEYSTORE_ID]="OpenAM PKI Keystore"
    [OPENAM_TRUSTSTORE_ID]="OpenAM PKI Truststore"
    [OPENAM_SSO_KEY_PASSWD]="OpenAM App Key"
    [OPENAM_ENCRYPTION_KEY]="OpenAM Encryption Key"
    [OPENAM_SSO_KEYSTORE_PASSWD]="OpenAM App Keystore"
    [OPENAM_CFG_SVC_ACCT]="OpenDJ Config Store Service Account"
    [OPENAM_CTS_SVC_ACCT]="OpenDJ CTS Store Service Account"
    [OPENAM_USR_SVC_ACCT]="OpenDJ User Store Service Account")

[ -f .odjpins ] &&  rm -f .odjpins
[ -f .tomcatpin ] &&  rm -rf .tomcatpin
[ -f .openampin ] &&  rm -rf .openampin
[ -f .sshpin ] &&  rm -f .sshpin
[ -f .dockerpin ] &&  rm -f .dockerpin

echo "#### Parsing config file"
ini_parser ${localInventoryFile}

echo "#### Setting up global variables"
ini_section_global
if [ $? -ne 0 ]; then
	echo "#### Error getting global variables"
    echo $USAGE >&2
	exit 1
fi

if [ -z "${gRemoteBuildDir}" ]; then
    gRemoteBuildDir=/tmp/zinet-build
fi

echo "#### Global Variables"
echo "#### ziD=${ziD}"
echo "#### ziNetEtcDir=${ziNetEtcDir}"
echo "#### ziTenantId=${ziTenantId}"
echo "#### gCaHostName=${gCaHostName}"
echo "#### gExternalCA=${gExternalCA}"
echo "#### gRepoKeyScan=${gRepoKeyScan}"
echo "#### gDirMgrDN=${gDirMgrDN}"
echo "#### gSearchDomains=${gSearchDomains}"
echo "#### gziAdmin=${gziAdmin}"
echo "#### gziAdminGrp=${gziAdminGrp}"
echo "#### gFetchRepoMode=${gFetchRepoMode}"
echo "#### gZinetRepoTar=${gZinetRepoTar}"
echo "#### gZinetRepoDir=${gZinetRepoDir}"
echo "#### gZinetCertDir=${gZinetCertDir}"
echo "#### gZinetConfigDir=${gZinetConfigDir}"
echo "#### gHaveSudo=${gHaveSudo}"
echo "#### gRemoteBuildDir=${gRemoteBuildDir}"
echo "#### gPKIExtCaRootName=${gPKIExtCaRootName}"
echo "#### gPKIExtCaSignName=${gPKIExtCaSignName}"
echo "#### gOpenAMAppKeystore=${gOpenAMAppKeystore}"

certFolder=
if [ "${gExternalCA}" == "true" ]; then
    [ -z "${gZinetCertDir}" ] \
        && certFolder="${localRepoFolder}/certs" \
        || certFolder="${localRepoFolder}/${gZinetCertDir}"
    mkdir -p "${certFolder}/private" 2> /dev/null
fi

repoKeys=
if [ ! -z ${gRepoKeyScan} ]; then
    echo "#### Setting up ${ZINET_TARGET_HOSTNAME} - pre-scanning keys"
    repoKeys=$(ssh-keyscan -t rsa ${gRepoKeyScan})
    exitOnErr  "$?" "pre-scanning keys"

    if [ -z "${repoKeys}" ]; then
        echo "#### Could not fetch repo keys"
        echo $USAGE >&2
        exit 1    
    fi
fi

############ Push code to targets

if [ "${localSkipRepoSync}" == "false" ]; then
    for serverId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "^server." | awk -F. '{ print $2 }' | sort -n); do
        echo
        echo "#### Processing entry = server.${serverId} (REPOS)"
    
        intializeServerSettings

        ini_section_server.${serverId}
        if [ $? -eq 0 ]; then

            printServerSettings

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "[ -d ${gRemoteBuildDir}/common ] && find ${gRemoteBuildDir} -mindepth 1 -maxdepth 1 -type d -print0 | xargs -0 rm -R"

            if [ "${gFetchRepoMode}" == "git" ]; then
                echo "#### Setting up ${ZINET_TARGET_HOSTNAME} - fetching via git"

                if [ ! -z "${repoKeys}" ]; then
                    SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "echo ${repoKeys} >> ~/.ssh/known_hosts"
                    exitOnErr  "$?" "Adding Repo Key"
                fi

                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "[ $(which git) ] && exit 0 || exit 1"
                if [ "$?" -ne 0 ] && [ "${gHaveSudo}" == "true" ]; then
                    echo "#### Setting up ${ZINET_TARGET_HOSTNAME} - Installing Git"
                    SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo apt-get -y update && sudo apt-get -y install git"
                    exitOnErr  "$?" "Installing Git"
                else
                    echo "#### Don't have sudo access. Aborting install"
                    exit 1
                fi

                # 1. Setup Repos
                echo "#### Setting up ${ZINET_TARGET_HOSTNAME} - fetching repos"
                for repoId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "repo." | awk -F. '{ print $2 }' | sort -n); do
                    echo
                    echo "#### Processing Repo = repo.${repoId}"

                    REPO_URI=
                    REPO_BRANCH=
                    REPO_ROOT=

                    ini_section_repo.${repoId}

                    echo "#### REPO_URI=${REPO_URI}"
                    echo "#### REPO_BRANCH=${REPO_BRANCH}"
                    echo "#### REPO_ROOT=${REPO_ROOT}"

                    if [ ! -z "${REPO_URI}" ]; then

                        theBranch=master
                        [ ! -z "${REPO_BRANCH}" ] && theBranch="${REPO_BRANCH}"

                        repoOpts=
                        [ ! -z "${REPO_ROOT}" ] && repoOpts=":${REPO_ROOT}"

                        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "git archive --remote=${REPO_URI} ${theBranch}${repoOpts} | tar -x -C ${gRemoteBuildDir}/"
                        exitOnErr  "$?" "Fetching Git repository"
                    else
                        echo "#### Can not load repo.${repoId} - REPO_URI not found"
                        exit 1        
                    fi
                done
            elif [ "${gFetchRepoMode}" == "tar" ] && [ -f "${localRepoFolder}/${gZinetRepoTar}" ]; then
                echo "#### Setting up ${ZINET_TARGET_HOSTNAME} - setting up via tar"

                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"

                SCP ${localRepoFolder}/${gZinetRepoTar} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "tar zxvf ${gRemoteBuildDir}/${gZinetRepoTar} -C ${gRemoteBuildDir}/"
            elif [ "${gFetchRepoMode}" == "dir" ] && [ ! -z "${gZinetRepoDir}" ] && [ -d "${localRepoFolder}/${gZinetRepoDir}" ]; then
                echo "#### Setting up ${ZINET_TARGET_HOSTNAME} - setting up via fetch mode"

                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"
                SCP -r ${localRepoFolder}/${gZinetRepoDir}/* ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                SCP -r ${localRepoFolder}/${gZinetConfigDir}/* ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
            else
                echo "#### Can find repo to push to server. I hope you know what youre doing."
            fi
        else
            echo "#### Could not find config for ini_section_server.${serverId}"
        fi
    done
fi

############ Process core services
 
for serverId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "^server." | awk -F. '{ print $2 }' | sort -n); do
    echo
    echo "#### Processing entry = server.${serverId} (CORE)"
    
    intializeServerSettings

    ini_section_server.${serverId}
    if [ $? -eq 0 ]; then

        printServerSettings

        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"
        
        # 1. Initialize ziNet
        if ${INSTALL_ZINET}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Initialize ziNet"

            zidOpts=
            [ ! -z "${ziD}" ] && zidOpts="-z ${ziD}"
            [ ! -z "${ZINET_ETCD_DIR}" ] \
                && zidOpts="${zidOpts} -Z ${ZINET_ETCD_DIR}" \
                || [ ! -z "${ziNetEtcDir}" ] && zidOpts="${zidOpts} -Z ${ziNetEtcDir}"

            deviceOpts=
            [ ! -z "${ZINET_STORAGE_DEV}" ] && deviceOpts="-d ${ZINET_STORAGE_DEV}"

            dataOpts=
            [ ! -z "${ZINET_DATA_DIR}" ] && dataOpts="-m ${ZINET_DATA_DIR}"

            searchOpts=
            [ ! -z "${gSearchDomains}" ] && searchOpts="-r \"${gSearchDomains}\""

            adminOpts=
            [ ! -z "${ZINET_ADMIN}" ] && adminOpts="-u ${ZINET_ADMIN}"
            if [ -z "${adminOpts}" ] && [ ! -z "${gziAdmin}" ]; then
                adminOpts="-u ${gziAdmin}"
            fi

            adminGrpOpts=
            [ ! -z "${ZINET_ADMIN_GRP}" ] && adminGrpOpts="-U ${ZINET_ADMIN_GRP}"
            if [ -z "${adminGrpOpts}" ] && [ ! -z "${gziAdminGrp}" ]; then
                adminGrpOpts="-U ${gziAdminGrp}"
            fi

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/common/bin/install-zinet.sh ${zidOpts} ${adminOpts} ${adminGrpOpts} -n ${ZINET_TARGET_HOSTNAME} ${deviceOpts} ${dataOpts} ${searchOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/common/bin/install-zinet.sh ${zidOpts} ${adminOpts} ${adminGrpOpts} -n ${ZINET_TARGET_HOSTNAME} ${deviceOpts} ${dataOpts} ${searchOpts}"
            exitOnErr  "$?" "Installing ziNet"
        fi

        # 2. Install Java
        if ${INSTALL_JAVA}; then
            echo            
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing Java"
            
            javaRootDirOpts=
            [ ! -z "${JAVA_ROOT_LOCATION}" ] && javaRootDirOpts="-p ${JAVA_ROOT_LOCATION}"
            
            if [ ! -z "${JAVA_REPO_FILENAME}" ] && [ -f "${localRepoFolder}/${JAVA_REPO_FILENAME}" ]; then
                if [ "${gHaveSudo}" == "true" ]; then
                    SCP ${localRepoFolder}/${JAVA_REPO_FILENAME} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/  \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/common/bin/install-java.sh -j ${gRemoteBuildDir}/${JAVA_REPO_FILENAME} ${javaRootDirOpts}"
                else
                    SCP ${localRepoFolder}/${JAVA_REPO_FILENAME} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/  \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/common/bin/install-java.sh -j ${gRemoteBuildDir}/${JAVA_REPO_FILENAME} ${javaRootDirOpts}"
                fi                
            elif [ ! -z "${JAVA_INSTALL_PKG}" ]; then
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/common/bin/install-java.sh -J ${JAVA_INSTALL_PKG} ${javaRootDirOpts}" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/common/bin/install-java.sh -J ${JAVA_INSTALL_PKG} ${javaRootDirOpts}"
            else
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/common/bin/install-java.sh ${javaRootDirOpts}" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/common/bin/install-java.sh ${javaRootDirOpts}"
            fi
            exitOnErr  "$?" "Installing Java"
        fi

        # 3. Install CA
        if $INSTALL_CA; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing CA Server"
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/ca/bin/install-ca.sh -c ${gRemoteBuildDir}/config" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/ca/bin/install-ca.sh -c ${gRemoteBuildDir}/config"
            exitOnErr  "$?" "Installing Certificate Authority"
            gCaHostName="${ZINET_TARGET_HOSTNAME}"
        fi

        echo "#### Determining PKI settings"
        pkiUser=
        pkiUserGrp=
        pkiUserOpts=
        if [ ! -z "${PKI_ADMIN}" ] && [ ! -z "${PKI_ADMIN_GRP}" ]; then
            pkiUser="${PKI_ADMIN}"
            pkiUserGrp="${PKI_ADMIN_GRP}"            
        fi
        if [ -z "${pkiUser}" ] && [ ! -z "${gziAdmin}" ] && [ ! -z "${gziAdminGrp}" ]; then
            pkiUser="${gziAdmin}"
            pkiUserGrp="${gziAdminGrp}"
        else
            pkiUser="pki"
            pkiUserGrp="pki"
        fi
        pkiUserOpts="-u ${pkiUser} -U ${pkiUserGrp}"

        # 4. Install PKI
        if ${INSTALL_PKI}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing PKI client"

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/pki/bin/install-pki.sh -c ${gRemoteBuildDir}/config ${pkiUserOpts}"
            exitOnErr  "$?" "Installing PKI"
        fi
       
        # 5. Generate CSR

        reqKeyPin=        
        if ${PKI_GENERATE_EXTCA_REQ}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Creating Cert"

            subjectOpts=
            [ ! -z "${PKI_CERT_SUBJECTNAME}" ] && subjectOpts="-s ${PKI_CERT_SUBJECTNAME}"

            dnsAliasOpts=
            [ ! -z "${PKI_CERT_SUBJECT_ALIASES}" ] && dnsAliasOpts="-d ${PKI_CERT_SUBJECT_ALIASES}"

            keyPinOpts=
            if [ ! -z "${PKI_KEYPIN_ID}" ]; then
                reqKeyPin=$(grep -w "${PKI_KEYPIN_ID}" "${localSecretsFile}" 2>/dev/null | awk -F= '{ print $2 }')
                if [ ! -z "${reqKeyPin}" ]; then
                    echo "#### ${ZINET_TARGET_HOSTNAME} - pushing keystore credentials"
                    echo -n "${reqKeyPin}" > .keypin
                    chmod 400 .keypin

                    keyPinOpts="-p ${gRemoteBuildDir}/.keypin"

                    SCP .keypin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown ${pkiUser}:${pkiUserGrp} ${gRemoteBuildDir}/.keypin && sudo chmod 400 ${gRemoteBuildDir}/.keypin" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown ${pkiUser}:${pkiUserGrp} ${gRemoteBuildDir}/.keypin && chmod 400 ${gRemoteBuildDir}/.keypin"
                fi
            fi

            echo "#### ${ZINET_TARGET_HOSTNAME} - Generating certificate request"
                if [ "${gHaveSudo}" == "true" ]; then
                    reqFileFiles=$(SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-request.sh ${subjectOpts} ${dnsAliasOpts} ${keyPinOpts}" | grep "CSR_FILE")
                    SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.keypin"
                else
                    reqFileFiles=$(SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-request.sh ${subjectOpts} ${dnsAliasOpts} ${keyPinOpts}" | grep "CSR_FILE")
                    SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.keypin"
                fi

            reqFile=$(echo "${reqFileFiles}" | grep -e "^CSR_FILE_REQUEST:" | awk -F: '{ print $2 }' | tr -d ' ')
            reqKey=$(echo "${reqFileFiles}" | grep -e "^CSR_FILE_KEY:" | awk -F: '{ print $2 }' | tr -d ' ')
            if [ -z "${reqKeyPin}" ]; then
                reqKeyPin=$(echo "${reqFileFiles}" | grep -e "^CSR_FILE_KEYPIN:" | awk -F: '{ print $2 }' | tr -d ' ')
            fi
            
            rm -f .keypin
        fi 

        # 6. Sign or Deploy Certs
        if [ "${gExternalCA}" == "false" ]; then

            if [ ! -z "${gCaHostName}" ]; then
                echo "#### ${ZINET_TARGET_HOSTNAME} - Copying certificate request to CA server (${gCaHostName})"
                SCP ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${reqFile} /tmp/
                SCP /tmp/$(basename ${reqFile}) ${userSSHOpts}${gCaHostName}:${gRemoteBuildDir}/

                echo "#### ${ZINET_TARGET_HOSTNAME} - Signing certificate request on ${gCaHostName}"
                [ "${gHaveSudo}" == "true" ] \
                    && fileList=$(SSH ${userSSHOpts}${gCaHostName} "sudo ${gRemoteBuildDir}/ca/bin/ca-sign-cert.sh -r ${gRemoteBuildDir}/$(basename ${reqFile})" | grep "CRT_FILE") \
                    || fileList=$(SSH ${userSSHOpts}${gCaHostName} "${gRemoteBuildDir}/ca/binca-sign-cert.sh -r ${gRemoteBuildDir}/$(basename ${reqFile})" | grep "CRT_FILE")

                certSignedOK=true

                echo "#### ${ZINET_TARGET_HOSTNAME} - Copying signed certificate from CA server (${gCaHostName})"
                certFile=$(echo "${fileList}" | grep -e "^CRT_FILE:" | awk -F: '{ print $2 }' | tr -d ' ')
                if [ ! -z "${certFile}" ]; then
                    certFileName=$(basename ${certFile})
                    SCP ${userSSHOpts}${gCaHostName}:${certFile} /tmp/
                    SCP /tmp/${certFileName} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${certFileName} \${ziNetEtcDir}/pki/server && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${certFileName}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && mv ${gRemoteBuildDir}/${certFileName} \${ziNetEtcDir}/pki/server && chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${certFileName}"
                else
                    certSignedOK=false
                    echo "#### ERROR: can't find cert file"
                fi

                echo "#### ${ZINET_TARGET_HOSTNAME} - Copying CA certificate from CA server (${gCaHostName})"
                caCertFile=$(echo "${fileList}" | grep -e "^CA_CRT_FILE:" | awk -F: '{ print $2 }' | tr -d ' ')
                if [ ! -z "${caCertFile}" ]; then
                    caCertFileName=$(basename ${caCertFile})
                    SCP ${userSSHOpts}${gCaHostName}:${caCertFile} /tmp/
                    SCP /tmp/${caCertFileName} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${caCertFileName} \${ziNetEtcDir}/pki/server && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${caCertFileName}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && mv ${gRemoteBuildDir}/${caCertFileName} \${ziNetEtcDir}/pki/server && chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${caCertFileName}"
                else
                    certSignedOK=false
                    echo "#### ERROR: can't find CA cert file"
                fi

                echo "#### ${ZINET_TARGET_HOSTNAME} - Copying root CA certificate from CA server (${gCaHostName})"
                rootCaCertFile=$(echo "${fileList}" | grep -e "^ROOT_CA_CRT_FILE:" | awk -F: '{ print $2 }' | tr -d ' ')
                if [ ! -z "${rootCaCertFile}" ]; then
                    rootCaCertFileName=$(basename ${rootCaCertFile})
                    SCP ${userSSHOpts}${gCaHostName}:${rootCaCertFile} /tmp/
                    SCP /tmp/${rootCaCertFileName} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${rootCaCertFileName} \${ziNetEtcDir}/pki/server && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${rootCaCertFileName}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && mv ${gRemoteBuildDir}/${rootCaCertFileName} \${ziNetEtcDir}/pki/server && chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${rootCaCertFileName}"
                else
                    certSignedOK=false
                    echo "#### ERROR: can't find CA cert file"
                fi

                if ${certSignedOK}; then
                    echo "#### ${ZINET_TARGET_HOSTNAME} - Installing CA Cert"
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${caCertFileName} -l && sudo ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${rootCaCertFileName} -l" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${caCertFileName} -l && ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${rootCaCertFileName} -l"

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Generating other certificates"
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-certs.sh ${subjectOpts}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-certs.sh ${subjectOpts}"

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Generating Java artifacts"
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-jks.sh ${subjectOpts}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-jks.sh ${subjectOpts}"

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Generating System Java artifacts"
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/pki/bin/pki-update-jrejks.sh ${subjectOpts}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-update-jrejks.sh ${subjectOpts}"

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Generating cert aliases"
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-aliases.sh ${subjectOpts}" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-aliases.sh ${subjectOpts}"
                fi
            else
                echo "#### ${ZINET_TARGET_HOSTNAME} - CA Server is undefined so server certificate can't be signed"
            fi
        else
            subjectOpts=
            [ ! -z "${PKI_CERT_SUBJECTNAME}" ] && subjectOpts="-s ${PKI_CERT_SUBJECTNAME}"

            if ${PKI_GENERATE_EXTCA_REQ}; then
                echo "#### ${ZINET_TARGET_HOSTNAME} - Generating certificate request for external CA"
                SCP ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${reqFile} ${certFolder}/
                SCP ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${reqKey} ${certFolder}/
        
                certFileName=$(basename ${reqFile})
                pinFileName=${certFileName%\.csr}

                echo "${reqKeyPin}" > ${certFolder}/private/${pinFileName}.pin
                chmod 400 ${certFolder}/private/${pinFileName}.pin
            elif [ "${PKI_DEPLOY_EXTCA_CERT}" == "true" ]; then
                ## See if the Certificate for the subject is in the certs folder.
                if [ -f "${certFolder}/${PKI_CERT_SUBJECTNAME}.crt" ]; then

                    certSignedOK=true

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Copying External signed certificate "
                    if [ -f "${certFolder}/${PKI_CERT_SUBJECTNAME}.crt" ] && [ -f "${certFolder}/${PKI_CERT_SUBJECTNAME}.key" ] && [ -f "${certFolder}/private/${PKI_CERT_SUBJECTNAME}.pin" ]; then
                        SCP ${certFolder}/${PKI_CERT_SUBJECTNAME}.{crt,key} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                        SCP ${certFolder}/private/${PKI_CERT_SUBJECTNAME}.pin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${PKI_CERT_SUBJECTNAME}.{crt,key} \${ziNetEtcDir}/pki/server/ && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${PKI_CERT_SUBJECTNAME}.{crt,key}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && mv ${gRemoteBuildDir}/${PKI_CERT_SUBJECTNAME}.{crt,key} \${ziNetEtcDir}/pki/server/ && chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${PKI_CERT_SUBJECTNAME}.{crt,key}"

                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${PKI_CERT_SUBJECTNAME}.pin \${ziNetEtcDir}/pki/server/private/ && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/private/${PKI_CERT_SUBJECTNAME}.pin && sudo chmod 440 \${ziNetEtcDir}/pki/server/private/${PKI_CERT_SUBJECTNAME}.pin" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${PKI_CERT_SUBJECTNAME}.pin \${ziNetEtcDir}/pki/server/private/ && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/private/${PKI_CERT_SUBJECTNAME}.pin && sudo chmod 440 \${ziNetEtcDir}/pki/server/private/${PKI_CERT_SUBJECTNAME}.pin"
                    else
                        certSignedOK=false
                        echo "#### ERROR: can't find cert file"
                    fi

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Copying External CA certificate"
                    caCertFile="${certFolder}/${gPKIExtCaSignName}"
                    if [ ! -z "${caCertFile}" ]; then
                        caCertFileName=$(basename ${caCertFile})
                        echo "#### pushing caCertFileName: $caCertFileName"
                        SCP ${caCertFile} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${caCertFileName} \${ziNetEtcDir}/pki/server && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${caCertFileName}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && mv ${gRemoteBuildDir}/${caCertFileName} \${ziNetEtcDir}/pki/server && chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${caCertFileName}"
                    else
                        certSignedOK=false
                        echo "#### ERROR: can't find CA cert file"
                    fi

                    echo "#### ${ZINET_TARGET_HOSTNAME} - Copying External Root CA certificate"
                    rootCaCertFile="${certFolder}/${gPKIExtCaRootName}"
                    if [ ! -z "${rootCaCertFile}" ]; then
                        rootCaCertFileName=$(basename ${rootCaCertFile})
                        echo "#### pushing rootCaCertFile: $rootCaCertFileName"
                        SCP ${rootCaCertFile} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo mv ${gRemoteBuildDir}/${rootCaCertFileName} \${ziNetEtcDir}/pki/server && sudo chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${rootCaCertFileName}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && mv ${gRemoteBuildDir}/${rootCaCertFileName} \${ziNetEtcDir}/pki/server && chown ${pkiUser}:${pkiUserGrp} \${ziNetEtcDir}/pki/server/${rootCaCertFileName}"
                    else
                        certSignedOK=false
                        echo "#### ERROR: can't find CA cert file"
                    fi

                    if ${certSignedOK}; then
                        echo "#### ${ZINET_TARGET_HOSTNAME} - Installing CA Cert"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && sudo ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${gPKIExtCaSignName} -l && sudo ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${gPKIExtCaRootName} -l" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "source /etc/default/zinet && ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${gPKIExtCaSignName} -l && ${gRemoteBuildDir}/pki/bin/pki-install-cacert.sh -f \${ziNetEtcDir}/pki/server/${gPKIExtCaRootName} -l"

                        echo "#### ${ZINET_TARGET_HOSTNAME} - Generating other certificates"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-certs.sh ${subjectOpts}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-certs.sh ${subjectOpts}"

                        grep -w "${PKI_KEYPIN_ID}" "${localSecretsFile}" > .pkipins
                        grep -w "${PKI_KEYSTORE_ID}" "${localSecretsFile}" >> .pkipins
                        grep -w "${PKI_TRUSTSTORE_ID}" "${localSecretsFile}" >> .pkipins

                        passwordOpts=
                        echo "#### ${ZINET_TARGET_HOSTNAME} - pushing .pkipins credentials"
                        passwordOpts="-Y ${gRemoteBuildDir}/.pkipins"

                        SCP .pkipins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown ${pkiUser}:${pkiUserGrp} ${gRemoteBuildDir}/.pkipins && sudo chmod 400 ${gRemoteBuildDir}/.pkipins" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chmod 400 ${gRemoteBuildDir}/.pkipins"

                        echo "#### ${ZINET_TARGET_HOSTNAME} - Generating Java artifacts"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-jks.sh ${subjectOpts} ${passwordOpts}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-jks.sh ${subjectOpts} ${passwordOpts}"

                        echo "#### ${ZINET_TARGET_HOSTNAME} - Generating System Java artifacts"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/pki/bin/pki-update-jrejks.sh ${subjectOpts}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-update-jrejks.sh ${subjectOpts}"
                    
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.pkipins" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.pkipins"

                        rm .pkipins

                        echo "#### ${ZINET_TARGET_HOSTNAME} - Generating cert aliases"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo -u ${pkiUser} ${gRemoteBuildDir}/pki/bin/pki-generate-aliases.sh ${subjectOpts}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-generate-aliases.sh ${subjectOpts}"
                    fi
                else
                    echo "#### Can't find certificate for ${PKI_CERT_SUBJECTNAME} in ${certFolder}"
                fi
            fi
        fi

        # 8. Install OpenDJ

        if $INSTALL_OPENDJ; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing OpenDJ Server"
            instanceOpts=
            [ ! -z "${OPENDJ_INSTANCE_ID}" ] && instanceOpts="-I ${OPENDJ_INSTANCE_ID}"

            instanceCfgDir=
            [ -z "${OPENDJ_INSTANCE_CFG_DIR}" ] && instanceCfgDir="${gRemoteBuildDir}/config" || instanceCfgDir="${gRemoteBuildDir}/${OPENDJ_INSTANCE_CFG_DIR}"

            zipOpts=
            if [ -f "${localRepoFolder}/${OPENDJ_ZIP_ARCHIVE}" ]; then
                zipOpts="-z ${gRemoteBuildDir}/${OPENDJ_ZIP_ARCHIVE}"
                SCP ${localRepoFolder}/${OPENDJ_ZIP_ARCHIVE} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
            else
                echo "#### Missing OpenDJ archive file. Continuing under the assumption that opendj is already deployed"
            fi

            extOpts=
            if [ ! -z "${OPENDJ_EXTENSIONS}" ]; then
                IFS=',' read -ra updtArr <<< "${OPENDJ_EXTENSIONS}"
                for theExtension in "${updtArr[@]}"; do
                    if [ -f "${localRepoFolder}/${theExtension}" ]; then
                        echo "#### Transferring extension file: ${theExtension}"
                        SCP ${localRepoFolder}/${theExtension} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                        [ -z "${extOpts}" ] && extOpts="-e ${gRemoteBuildDir}/${theExtension}" || extOpts="${extOpts},${gRemoteBuildDir}/${theExtension}"
                    else
                        echo "#### Can't find extension file: ${theExtension}"                    
                    fi            
                done
            fi
            
            subjectOpts=
            [ ! -z "${OPENDJ_CERT_SUBJECTNAME}" ] && subjectOpts="-s ${OPENDJ_CERT_SUBJECTNAME}"

            nodeOpts=
            [ ! -z "${OPENDJ_NODE_TEMPLATE}" ] && nodeOpts="-t ${OPENDJ_NODE_TEMPLATE}"
            
            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .odjpins ] && copyPasswordFile .odjpins opendjPasswds "${localSecretsFile}"

            passwordOpts=
            if [ -f .odjpins ]; then
                echo "#### ${ZINET_TARGET_HOSTNAME} - pushing ${gDirMgrDN} credentials"
                passwordOpts="-D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins"

                SCP .odjpins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.odjpins && sudo chmod 400 ${gRemoteBuildDir}/.odjpins" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.odjpins && chmod 400 ${gRemoteBuildDir}/.odjpins"
            fi

            echo "#### Performing install-opendj.sh"
            [ -z "${DEPLOY_TENANT_ID}" ] && DEPLOY_TENANT_ID="${ziTenantId}"
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/install-opendj.sh -T ${DEPLOY_TENANT_ID} -c ${instanceCfgDir} ${instanceOpts} ${extOpts} ${zipOpts} ${nodeOpts} ${passwordOpts} ${subjectOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/install-opendj.sh -T ${DEPLOY_TENANT_ID} -c ${instanceCfgDir} ${instanceOpts} ${extOpts} ${zipOpts} ${nodeOpts} ${passwordOpts} ${subjectOpts}"
            exitOnErr  "$?" "Installing OpenDJ"

            echo "#### Performing configure-opendj.sh"
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/configure-opendj.sh ${passwordOpts} ${instanceOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/configure-opendj.sh ${passwordOpts} ${instanceOpts}"
            exitOnErr  "$?" "Configuring OpenDJ"

            echo "#### Performing seed-opendj.sh"
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/seed-opendj.sh ${instanceOpts} ${passwordOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/seed-opendj.sh ${instanceOpts} ${passwordOpts}"
            exitOnErr  "$?" "Deploying OpenDJ"

            policyInstOpts=
            [ ! -z "${DEPLOY_POLICY_ID}" ] && policyInstOpts="-p ${DEPLOY_POLICY_ID}"

            echo "#### Preparing to deploy password policies"
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/opendj-setup-passwd-config.sh ${policyInstOpts} ${instanceOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/opendj-setup-passwd-config.sh ${policyInstOpts} ${instanceOpts}"
            exitOnErr  "$?" "Deploying OpenDJ password policy"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.odjpins" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.odjpins"
        fi

        # 9. Install NGINX

        if ${INSTALL_NGINX}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing NGINX module"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/nginx/bin/install-nginx.sh -c ${gRemoteBuildDir}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/nginx/bin/install-nginx.sh -c ${gRemoteBuildDir}"
            exitOnErr  "$?" "Installing NGINX"
        fi

        # 10. Install FAIL2BAN

        if ${INSTALL_FAIL2BAN}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing fail2ban module"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/fail2ban/bin/install-fail2ban.sh -c ${gRemoteBuildDir}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/fail2ban/bin/install-fail2ban.sh -c ${gRemoteBuildDir}"
            exitOnErr  "$?" "Installing Fail2ban"
        fi

    else
    	echo "#### Could not find config for ini_section_server.${serverId}"
    fi
done

############ Replicating servers

for serverId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "^server." | awk -F. '{ print $2 }' | sort -n); do
    echo
    echo "#### Replicating servers = server.${serverId} (DEPLOY)"

    intializeServerSettings

    ini_section_server.${serverId}
    if [ $? -eq 0 ]; then

        printServerSettings

        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"

        # 1. Replicate OpenDJ
        
        if $REPLICATE_OPENDJ; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Replicating opendj schema"
            instanceOpts=
            if [ ! -z "${OPENDJ_INSTANCE_ID}" ]; then
                instanceOpts="-I ${OPENDJ_INSTANCE_ID}"
            fi

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
             [ ! -f .odjpins ] && copyPasswordFile .odjpins opendjPasswds "${localSecretsFile}"

            passwordOpts=
            if [ -f .odjpins ]; then
                echo "#### ${ZINET_TARGET_HOSTNAME} - pushing ${gDirMgrDN} credentials"
                passwordOpts="-D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins"

                SCP .odjpins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.odjpins && sudo chmod 400 ${gRemoteBuildDir}/.odjpins" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.odjpins && chmod 400 ${gRemoteBuildDir}/.odjpins"
            fi

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/replicate-opendj.sh ${instanceOpts} ${passwordOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/replicate-opendj.sh ${instanceOpts} ${passwordOpts}"
            exitOnErr  "$?" "Replicating OpenDJ"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.odjpins" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.odjpins"            
        fi

    else
    	echo "#### Could not find config for ini_section_server.${serverId}"
    fi
done


############ Deploy tenants and schemas

for serverId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "^server." | awk -F. '{ print $2 }' | sort -n); do
    echo
    echo "#### Deploy tenants and schemas = server.${serverId} (DEPLOY)"

    intializeServerSettings

    ini_section_server.${serverId}
    if [ $? -eq 0 ]; then

        printServerSettings

        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"

        # 1. Deploy tenants

        if $DEPLOY_TENANT; then

            echo "#### ${ZINET_TARGET_HOSTNAME} - Deploying tenant schemas"

            passwordOpts=
            if [ -f .odjpins ]; then
                echo "#### ${ZINET_TARGET_HOSTNAME} - pushing ${gDirMgrDN} credentials"
                passwordOpts="-D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins"

                SCP .odjpins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.odjpins && sudo chmod 400 ${gRemoteBuildDir}/.odjpins" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.odjpins && chmod 400 ${gRemoteBuildDir}/.odjpins"
            fi

            [ -z "${DEPLOY_TENANT_ID}" ] && DEPLOY_TENANT_ID="${ziTenantId}"
            IFS=' ' read -ra theTenants  <<< "${DEPLOY_TENANT_ID}"
            for tiD in "${theTenants[@]}"; do
                echo "#### Preparing to deploy tenant: ${tiD}"
                tenantPasswordOpts=
                tenantSecrets=$(grep "OPENDJ_${tiD}" "${localSecretsFile}" 2>/dev/null)
    
                if [ ! -z "${tenantSecrets}" ]; then
                    echo "#### ${ZINET_TARGET_HOSTNAME} - pushing tenant ${tiD} credentials"
                    echo "${tenantSecrets}" > .tenant
                    chmod 400 .tenant
                    
                    tenantPasswordOpts="-P ${gRemoteBuildDir}/.tenant"

                    SCP .tenant ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}
                    [ "${gHaveSudo}" == "true" ] \
                        && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chmod 400 ${gRemoteBuildDir}/.tenant" \
                        || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chmod 400 ${gRemoteBuildDir}/.tenant"
                fi

                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/opendj-deploy-tenant.sh -t ${tiD} ${instanceOpts} ${passwordOpts} ${tenantPasswordOpts}" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/opendj-deploy-tenant.sh -t ${tiD} ${instanceOpts} ${passwordOpts} ${tenantPasswordOpts}"
                exitOnErr  "$?" "Deploying OpenDJ tenant"

                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.tenant" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.tenant"
                rm -f .tenant
            done
        fi

        # 2. Deploy SSHLDAP
        if $DEPLOY_SSHLDAP; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Deploying sshldap schema"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .odjpins ] && copyPasswordFile .odjpins opendjPasswds "${localSecretsFile}"

            SCP .odjpins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.odjpins && sudo chmod 400 ${gRemoteBuildDir}/.odjpins" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.odjpins && chmod 400 ${gRemoteBuildDir}/.odjpins"

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/sshldap/bin/deploy-sshldap.sh -c ${gRemoteBuildDir}/config -l ${gRemoteBuildDir}/sshldap/ldif -D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins ${sshldapPasswordOpts}"
            exitOnErr  "$?" "Deploying SSHLDAP"

            for f in ${SSHLDAP_FABRIC_LIST}; do
                echo "#### ${ZINET_TARGET_HOSTNAME} - Deploying sshldap fabric ${f}"
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/sshldap/bin/sshldap-add-fabric.sh -l ${gRemoteBuildDir}/sshldap/${f} -D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/sshldap/bin/sshldap-add-fabric.sh -l ${gRemoteBuildDir}/sshldap/${f} -D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins"
                exitOnErr  "$?" "Deploying SSHLDAP fabric"
            done

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.odjpins" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.odjpins"
        fi

        # 3. Deploy Docker
        if $DEPLOY_DOCKER; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Deploying docker schema"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .odjpins ] && copyPasswordFile .odjpins opendjPasswds "${localSecretsFile}"

            SCP .odjpins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.odjpins && sudo chmod 400 ${gRemoteBuildDir}/.odjpins" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.odjpins && chmod 400 ${gRemoteBuildDir}/.odjpins"

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/docker/bin/deploy-docker.sh -l ${gRemoteBuildDir}/docker/ldif -C ${gRemoteBuildDir}/config/docker-config.properties -D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins"
            exitOnErr  "$?" "Deploying Docker"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.odjpins" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.odjpins"
        fi
    else
    	echo "#### Could not find config for ini_section_server.${serverId}"
    fi
done

##### now install any components that may be dependent on LDAP

for serverId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "^server." | awk -F. '{ print $2 }' | sort -n); do
    echo
    echo "#### Deploying applications = server.${serverId} (APPS)"

    intializeServerSettings

    ini_section_server.${serverId}
    if [ $? -eq 0 ]; then

        printServerSettings

        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"

        # 1. Install SSHLDAP Fabric

        if ${INSTALL_SSHLDAP}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing SSHLDAP module"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .sshpin ] && copyPasswordFile .sshpin sshPasswds "${localSecretsFile}"

            if [ -z "${SSHLDAP_TENANT_ID}" ]; then
                SSHLDAP_TENANT_ID="${ziTenantId}"
            fi

            passwordOpts=
            if [ -f .sshpin ]; then
                passwordOpts="-A ${gRemoteBuildDir}/.sshpin"

                SCP .sshpin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.sshpin && sudo chmod 400 ${gRemoteBuildDir}/.sshpin" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.sshpin && chmod 400 ${gRemoteBuildDir}/.sshpin"
            fi

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/sshldap/bin/install-sshldap.sh -c ${gRemoteBuildDir}/config -i ${SSHLDAP_FABRIC_HOST_ID} -t ${SSHLDAP_TENANT_ID}  ${passwordOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/sshldap/bin/install-sshldap.sh -c ${gRemoteBuildDir}/config -i ${SSHLDAP_FABRIC_HOST_ID} -t ${SSHLDAP_TENANT_ID}  ${passwordOpts}"
            exitOnErr  "$?" "Installing SSHLDAP"

            if [ -f .sshpin ]; then
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.sshpin" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.sshpin"
            fi            
        fi

        # 2. Install SSHLDAP Fabric

        if ${INSTALL_DOCKER}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing docker module"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .dockerpin ] && copyPasswordFile .dockerpin dockerPasswds "${localSecretsFile}"

            passwordOpts=
            if [ -f .dockerpin ]; then
                passwordOpts="-Y ${gRemoteBuildDir}/.dockerpin"

                SCP .dockerpin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.dockerpin && sudo chmod 400 ${gRemoteBuildDir}/.dockerpin" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.dockerpin && chmod 400 ${gRemoteBuildDir}/.dockerpin"
            fi

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/docker/bin/install-docker.sh -c ${gRemoteBuildDir}/config ${passwordOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/docker/bin/install-docker.sh -c ${gRemoteBuildDir}/config ${passwordOpts}"
            exitOnErr  "$?" "Installing Docker"

            if [ -f .dockerpin ]; then
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.dockerpin" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.dockerpin"
            fi
        fi

        # 3. Install Tomcat

        if ${INSTALL_TOMCAT}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing Tomcat module"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .tomcatpin ] && copyPasswordFile .tomcatpin tomcatPasswds "${localSecretsFile}"

            tarOpts=
            if [ ! -z "${TOMCAT_TAR_FILENAME}" ] && [ -f "${localRepoFolder}/${TOMCAT_TAR_FILENAME}" ]; then
                SCP ${localRepoFolder}/${TOMCAT_TAR_FILENAME} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                tarOpts="-t ${gRemoteBuildDir}/${TOMCAT_TAR_FILENAME}"
            elif [ ! -z "${TOMCAT_INSTALL_PKG}" ]; then
                echo "#### Installing Tomcat package not yet supported"
                ## TODO: implement
                exit 1                                
            else
                echo "#### Installing Tomcat default package not yet supported"
                ## TODO: implement
                exit 1
            fi

            passwordOpts=
            if [ -f .tomcatpin ]; then
                passwordOpts="-Y ${gRemoteBuildDir}/.tomcatpin"

                SCP .tomcatpin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.tomcatpin && sudo chmod 400 ${gRemoteBuildDir}/.tomcatpin" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.tomcatpin && chmod 400 ${gRemoteBuildDir}/.tomcatpin"
            fi

            configOpts="-c ${gRemoteBuildDir}/config"
            [ ! -z ${TOMCAT_CONFIG_DIR} ] && configOpts="-c ${gRemoteBuildDir}/${TOMCAT_CONFIG_DIR}"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/tomcat/bin/install-tomcat.sh ${configOpts} ${passwordOpts} ${tarOpts}" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/tomcat/bin/install-tomcat.sh ${configOpts} ${passwordOpts} ${tarOpts}"
            exitOnErr  "$?" "Installing Tomcat"

            if [ -f .tomcatpin ]; then
                [ "${gHaveSudo}" == "true" ] \
                    && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.tomcatpin" \
                    || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.tomcatpin"
            fi
        fi

        # 4. Install OpenAM

        if ${INSTALL_OPENAM}; then
            echo
            echo "#### ${ZINET_TARGET_HOSTNAME} - Installing OpenAM module"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .openampin ] && copyPasswordFile .openampin openamPasswds "${localSecretsFile}"

            passwordOpts=
            if [ -f .openampin ]; then
                passwordOpts="-D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.openampin"
                secretsOpts="-Y ${gRemoteBuildDir}/.openampin"
                SCP .openampin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.openampin && sudo chmod 400 ${gRemoteBuildDir}/.openampin"
            fi

            configOpts="-c ${gRemoteBuildDir}/config"
            [ ! -z ${OPENAM_CONFIG_DIR} ] && configOpts="-c ${gRemoteBuildDir}/${OPENAM_CONFIG_DIR}"

            nodeOpts=
            [ ! -z "${OPENAM_NODE_TEMPLATE}" ] && nodeOpts="-t ${OPENAM_NODE_TEMPLATE}"

            echo "#### Transferring ${OPENAM_ZIP_ARCHIVE} ==> ${ZINET_TARGET_HOSTNAME}"
            SCP ${localRepoFolder}/${OPENAM_ZIP_ARCHIVE} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
            exitOnErr  "$?" "Preparing OpenAM: ${localRepoFolder}/${OPENAM_ZIP_ARCHIVE}"

            bHasUpdates=false
            localUpdateFileList=
            if [ ! -z "${OPENAM_UPDATE_LIST}" ]; then
                IFS=',' read -ra updtArr <<< "${OPENAM_UPDATE_LIST}"
                for updateFile in "${updtArr[@]}"; do
                    echo "#### Transferring update file: ${updateFile}"
                    SCP ${localRepoFolder}/${updateFile} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                    exitOnErr  "$?" "Preparing OpenAM: ${localRepoFolder}/${updateFile}"
                    [ -z "${localUpdateFileList}" ] && localUpdateFileList="-u ${gRemoteBuildDir}/${updateFile}" || localUpdateFileList="${localUpdateFileList},${gRemoteBuildDir}/${updateFile}"
                done
                bHasUpdates=true
            fi

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/openam/bin/install-openam.sh ${configOpts} ${passwordOpts} -z ${gRemoteBuildDir}/${OPENAM_ZIP_ARCHIVE} ${nodeOpts}"
            exitOnErr  "$?" "Installing OpenAM"

            if [ "${OPENAM_NEED_SEED}" == "true" ]; then
                restartOpt="-R restartWait"
                
                ## defer the restart until the updates are installed
                [ "${bHasUpdates}" == "true" ] && restartOpt=
                
                if [ "${OPENAM_KEYSTORE_SEED_SVR}" == "true" ]; then
                    echo "Seeding ${gOpenAMAppKeystore} <== ${ZINET_TARGET_HOSTNAME}"
                    resultStr=$(SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/openam/bin/openam-ops-keystores.sh ${secretsOpts} ${restartOpt}")
                    echo "${resultStr}"
                    keyStore=$(grep -e "^KEYSTORE:" <<< "${resultStr}" | grep "KEYSTORE" | awk -F: '{ print $2 }' | tr -d ' ')
                    if [ ! -z "${keyStore}" ]; then
                        echo "#### Transferring keyStore: ${keyStore}"
                        SCP ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${keyStore} ${localRepoFolder}/${gOpenAMAppKeystore}
                        exitOnErr  "$?" "Transferring OpenAM keyStore"
                        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${keyStore}"
                    else
                        exitOnErr  "1" "Installing OpenAM keyStore"
                    fi
                elif [ -f "${localRepoFolder}/${gOpenAMAppKeystore}" ]; then
                    echo "Pushing ${gOpenAMAppKeystore} ==> ${ZINET_TARGET_HOSTNAME}"
                    SCP ${localRepoFolder}/${gOpenAMAppKeystore} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/${gOpenAMAppKeystore}
                    exitOnErr  "$?" "Pushing OpenAM keyStore"
                    SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/openam/bin/openam-ops-keystores.sh ${secretsOpts} ${restartOpt} -k ${gRemoteBuildDir}/${gOpenAMAppKeystore}"
                    exitOnErr  "$?" "Installing OpenAM keyStore"
                    SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/${gOpenAMAppKeystore}"
                fi
            fi

            if [ "${bHasUpdates}" == "true" ]; then
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/openam/bin/openam-ops-updater.sh ${localUpdateFileList} -R restart"
                exitOnErr  "$?" "Updating OpenAM"
            fi

            if [ -f .openampin ]; then
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.openampin"
            fi
        fi
        
        # 5. Deploy config
        if ${OPENAM_DEPLOY_CONFIG}; then
            echo
            echo "#### Preparing to deploy OpenAM config on ${ZINET_TARGET_HOSTNAME}"

            echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
            [ ! -f .openampin ] && copyPasswordFile .openampin openamPasswds "${localSecretsFile}"

            configOpts="-c ${gRemoteBuildDir}/config"
            [ ! -z ${OPENAM_CONFIG_DIR} ] && configOpts="-c ${gRemoteBuildDir}/${OPENAM_CONFIG_DIR}"

            passwordOpts=
            if [ -f .openampin ]; then
                passwordOpts="-Y ${gRemoteBuildDir}/.openampin"
                SCP .openampin ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chmod 400 ${gRemoteBuildDir}/.openampin"
            fi

            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/openam/bin/configure-openam.sh ${configOpts} ${passwordOpts}"
            exitOnErr  "$?" "Configuring OpenAM"

            if [ -f .openampin ]; then
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.openampin"
            fi        
        fi

        
    else
    	echo "#### Could not find config for ini_section_server.${serverId}"
    fi
done

##### Apply any updates and maintenance

for serverId in $(grep -e "\[*\]" ${localInventoryFile} | tr -d '[' | tr -d ']' | tr -d ' ' | grep "^server." | awk -F. '{ print $2 }' | sort -n); do
    echo
    echo "#### Maintaining servers = server.${serverId} (OPS)"

    intializeServerSettings

    ini_section_server.${serverId}
    if [ $? -eq 0 ]; then

        printServerSettings

        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "mkdir -p ${gRemoteBuildDir} 2> /dev/null"

        # 1. Apply patches to OpenAM
        if ${UPDATEER_OPENAM_APPLY_PATCHES}; then
            echo "#### Preparing to update OpenAM config on ${ZINET_TARGET_HOSTNAME}"

            bHasUpdates=false
            localUpdateFileList=
            if [ ! -z "${OPENAM_UPDATE_LIST}" ]; then
                IFS=',' read -ra updtArr <<< "${OPENAM_UPDATE_LIST}"
                for updateFile in "${updtArr[@]}"; do
                    echo "#### Transferring update file: ${updateFile}"
                    SCP ${localRepoFolder}/${updateFile} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                    exitOnErr  "$?" "Preparing OpenAM: ${localRepoFolder}/${updateFile}"
                    [ -z "${localUpdateFileList}" ] && localUpdateFileList="-u ${gRemoteBuildDir}/${updateFile}" || localUpdateFileList="${localUpdateFileList},${gRemoteBuildDir}/${updateFile}"
                done
                bHasUpdates=true
            fi

            if [ ! -z "${localUpdateFileList}" ]; then
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/openam/bin/openam-ops-updater.sh ${localUpdateFileList} -R restartWait"
                exitOnErr  "$?" "Updating OpenAM"
            else
                echo "#### No updates were specified. Nothing updated."            
            fi

            if [ -f .openampin ]; then
                SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.openampin"
            fi
        fi

        # 2. Update System PKI
        if ${UPDATER_PKI_JREJKS}; then        
            echo "#### ${ZINET_TARGET_HOSTNAME} - Generating System Java artifacts"

            [ "${gHaveSudo}" == "true" ] \
                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/pki/bin/pki-update-jrejks.sh" \
                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/pki/bin/pki-update-jrejks.sh"
        fi

        # 3. Ops - maintenance
        if [ ! -z "${OPENDJ_OPS_MAINT}" ]; then
            echo "#### ${ZINET_TARGET_HOSTNAME} - Preparing to perform maintenance"

            instanceOpts=
            [ ! -z "${OPENDJ_INSTANCE_ID}" ] && instanceOpts="-I ${OPENDJ_INSTANCE_ID}"

            IFS=',' read -ra xInstanceArr <<< "${OPENDJ_OPS_MAINT}"

            for cmd in "${xInstanceArr[@]}"; do

                case "$cmd" in
                    "resync-server")
                        echo
                        echo "#### ${ZINET_TARGET_HOSTNAME} - Updating OpenDJ Server"
                        instanceCfgDir=
                        [ -z "${OPENDJ_INSTANCE_CFG_DIR}" ] && instanceCfgDir="${gRemoteBuildDir}/config" || instanceCfgDir="${gRemoteBuildDir}/${OPENDJ_INSTANCE_CFG_DIR}"

                        extOpts=
                        for theExtension in ${OPENDJ_EXTENSIONS}; do
                            if [ -f "${localRepoFolder}/${theExtension}" ]; then
                                SCP ${localRepoFolder}/${theExtension} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                                [ -z "${extOpts}" ] && extOpts="-e ${gRemoteBuildDir}/${theExtension}" || extOpts="${extOpts},${gRemoteBuildDir}/${theExtension}"
                            fi            
                        done

                        echo "#### ${ZINET_TARGET_HOSTNAME} - preparing credentials"
                        [ ! -f .odjpins ] && copyPasswordFile .odjpins opendjPasswds "${localSecretsFile}"

                        passwordOpts=
                        if [ -f .odjpins ]; then
                            echo "#### ${ZINET_TARGET_HOSTNAME} - pushing ${gDirMgrDN} credentials"
                            passwordOpts="-D \"${gDirMgrDN}\" -Y ${gRemoteBuildDir}/.odjpins"

                            SCP .odjpins ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                            [ "${gHaveSudo}" == "true" ] \
                                && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo chown root:root ${gRemoteBuildDir}/.odjpins && sudo chmod 400 ${gRemoteBuildDir}/.odjpins" \
                                || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "chown root:root ${gRemoteBuildDir}/.odjpins && chmod 400 ${gRemoteBuildDir}/.odjpins"
                        fi

                        echo "#### Performing update-opendj.sh"
                        [ -z "${DEPLOY_TENANT_ID}" ] && DEPLOY_TENANT_ID="${ziTenantId}"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/update-opendj.sh -T ${DEPLOY_TENANT_ID} -c ${instanceCfgDir} ${instanceOpts} ${extOpts} ${passwordOpts}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/update-opendj.sh -T ${DEPLOY_TENANT_ID} -c ${instanceCfgDir} ${instanceOpts} ${extOpts} ${passwordOpts}"
                        exitOnErr  "$?" "Installing OpenDJ"

                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo rm -f ${gRemoteBuildDir}/.odjpins" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "rm -f ${gRemoteBuildDir}/.odjpins"
                        ;;
                    "rebuild-degraded")
                        echo "#### Preparing to rebuild degraded indexes"
                        [ "${gHaveSudo}" == "true" ] \
                            && SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/opendj-ops-rebuild-degraded.sh ${instanceOpts}" \
                            || SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/opendj-ops-rebuild-degraded.sh ${instanceOpts}"
                        ;;
                    "schedule-backup")
                        echo "#### Scheduling backups"
                        instanceCfgDir=
                        [ -z "${OPENDJ_INSTANCE_CFG_DIR}" ] && instanceCfgDir="${gRemoteBuildDir}/config" || instanceCfgDir="${gRemoteBuildDir}/${OPENDJ_INSTANCE_CFG_DIR}"
                        
                        SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "${gRemoteBuildDir}/opendj/bin/opendj-configure-backups.sh -p ${instanceCfgDir}/${OPENDJ_OPS_MAINT_POLICY} ${instanceOpts}"
                        ;;            
                    "apply-patches")
                        echo "#### Preparing to patch OpenDJ ${ZINET_TARGET_HOSTNAME}"

                        bHasUpdates=false
                        localUpdateFileList=
                        if [ ! -z "${OPENDJ_EXTENSIONS}" ]; then
                            IFS=',' read -ra updtArr <<< "${OPENDJ_EXTENSIONS}"
                            for updateFile in "${updtArr[@]}"; do
                                echo "#### Transferring update file: ${updateFile}"
                                SCP ${localRepoFolder}/${updateFile} ${userSSHOpts}${ZINET_TARGET_HOSTNAME}:${gRemoteBuildDir}/
                                exitOnErr  "$?" "Preparing OpenDJ: ${localRepoFolder}/${updateFile}"
                                [ -z "${localUpdateFileList}" ] && localUpdateFileList="-u ${gRemoteBuildDir}/${updateFile}" || localUpdateFileList="${localUpdateFileList},${gRemoteBuildDir}/${updateFile}"
                            done
                            bHasUpdates=true
                        fi

                        if [ ! -z "${localUpdateFileList}" ]; then
                            SSH ${userSSHOpts}${ZINET_TARGET_HOSTNAME} "sudo ${gRemoteBuildDir}/opendj/bin/opendj-ops-updater.sh ${localUpdateFileList} -R restartWait ${instanceOpts}"
                            exitOnErr  "$?" "Updating OpenAM"
                        else
                            echo "#### No updates were specified. Nothing updated."            
                        fi
                        ;;
                esac
            done
        fi
        
    else
    	echo "#### Could not find config for ini_section_server.${serverId}"
    fi
done

[ -f .odjpins ] &&  rm -f .odjpins
[ -f .tomcatpin ] &&  rm -rf .tomcatpin
[ -f .openampin ] &&  rm -rf .openampin
[ -f .sshpin ] &&  rm -f .sshpin
[ -f .dockerpin ] &&  rm -f .dockerpin

