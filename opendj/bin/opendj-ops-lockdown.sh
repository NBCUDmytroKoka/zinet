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
		exit 1
fi

lockdownMode=
: ${instanceRoot=}

USAGE="	Usage: `basename $0` [ -l enter | exit ] [ -I instanceRoot ]"

while getopts hu:R:I: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            cd ${SAVE_DIR}
            exit 0
            ;;
        l)
            lockdownMode="$OPTARG"
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

if [ "${lockdownMode}" != "enter" ] && [ "${lockdownMode}" != "exit" ]; then
	echo "Must pass a lockdownMode"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

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

for f in ${ziNetEtcDir}/*.functions; do source $f; done 2> /dev/null
for f in ${ziNetEtcDir}/*.properties; do source $f; done 2> /dev/null

opendjCfgDir=${ziNetEtcDir}/opendj
if [ ! -z ${instanceRoot} ]; then
    opendjCfgDir="${opendjCfgDir}/${instanceRoot}"
fi

for f in ${opendjCfgDir}/*.functions; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-default.properties; do source $f; done 2> /dev/null
for f in ${opendjCfgDir}/opendj-*-override.properties; do source $f; done 2> /dev/null

tmpLockdown=$(mktemp /tmp/.XXXXXXXXXXXX)

if [ "${lockdownMode}" == "enter" ]; then

	echo "#### Entering lockdown mode"
	cat <<- EOF > ${tmpLockdown}
	dn: ds-task-id=Enter Lockdown Mode,cn=Scheduled Tasks,cn=tasks
	objectClass: top
	objectClass: ds-task
	ds-task-id: Enter Lockdown Mode
	ds-task-class-name: org.opends.server.tasks.EnterLockdownModeTask
EOF

else
	echo "#### Leaving lockdown mode"
	cat <<- EOF > ${tmpLockdown}
	dn: ds-task-id=Leave Lockdown Mode,cn=Scheduled Tasks,cn=tasks
	objectClass: top
	objectClass: ds-task
	ds-task-id: Leave Lockdown Mode
	ds-task-class-name: org.opends.server.tasks.LeaveLockdownModeTask
EOF

fi

localDirMgrDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

tempPin=$(mktemp /tmp/."XXXXXXXXXXXXXXX")
echo -n "${localLDAPBindPW}" > "${tempPin}"
chmod 400 "${tempPin}"

export LDAPTLS_CACERT=$(find "${ziNetEtcDir}/pki/server" -name "*-cachain.crt" 2>/dev/null | head -1)
ldapmodify -vvv \
-H ${OPENDJ_LDAP_SERVER_URI} \
-D "${localDirMgrDN}"       \
-y ${tempPin}               \
-f ${tmpLockdown}
 
rm -f ${tmpLockdown}
rm -f ${tempPin}

cd ${SAVE_DIR}
