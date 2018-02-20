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

: ${instanceRoot=}

localAction=${1}
[ ! -z "${2}" ] && instanceRoot=${2}
USAGE="	Usage: `basename $0` start | startWait | stop | stopWait | restart | restartWait  [ instanceRoot ]"

if [ -z "${localAction}" ]; then
	echo "Must pass a valid action"
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

serviceName=opendj
if [ ! -z "${OPENDJ_SCV_NAME}" ]; then
    serviceName="${OPENDJ_SCV_NAME}"
elif [ ! -z "${instanceRoot}" ]; then
    serviceName="${instanceRoot}"
fi

time {
if [ "$(pidof systemd)" ]; then
    echo "#### ${localAction} systemd service: ${serviceName}"

    if [ "${localAction}" == "start" ]; then
        systemctl start ${serviceName}.service
    elif [ "${localAction}" == "startWait" ]; then
        systemctl start ${serviceName}.service
        waitForOpenDJToStart $(hostname) ${OPENDJ_ADMIN_PORT}
    elif [ "${localAction}" == "stop" ]; then
        systemctl stop ${serviceName}.service
    elif [ "${localAction}" == "stopWait" ]; then
        systemctl stop ${serviceName}.service
        waitForOpenDJToStop $(hostname) ${OPENDJ_ADMIN_PORT}
    elif [ "${localAction}" == "restart" ]; then
        systemctl stop ${serviceName}.service
        systemctl start ${serviceName}.service    
    elif [ "${localAction}" == "restartWait" ]; then
        systemctl stop ${serviceName}.service
        waitForOpenDJToStop $(hostname) ${OPENDJ_ADMIN_PORT}

        systemctl start ${serviceName}.service    
        waitForOpenDJToStart $(hostname) ${OPENDJ_ADMIN_PORT}
    fi
else
    echo "#### ${localAction} SysV service: ${serviceName}"
    if [ "${localAction}" == "start" ]; then
        service ${serviceName} start    
    elif [ "${localAction}" == "startWait" ]; then
        service ${serviceName} start
        waitForOpenDJToStart $(hostname) ${OPENDJ_ADMIN_PORT}
    elif [ "${localAction}" == "stop" ]; then
        service ${serviceName} stop
    elif [ "${localAction}" == "stopWait" ]; then
        service ${serviceName} stop
        waitForOpenDJToStop $(hostname) ${OPENDJ_ADMIN_PORT}    
    elif [ "${localAction}" == "restart" ]; then
        service ${serviceName} stop
        service ${serviceName} start
    elif [ "${localAction}" == "restartWait" ]; then
        service ${serviceName} stop
        waitForOpenDJToStop $(hostname) ${OPENDJ_ADMIN_PORT}

        service ${serviceName} start
        waitForOpenDJToStart $(hostname) ${OPENDJ_ADMIN_PORT}
    fi
fi
}

cd ${SAVE_DIR}
