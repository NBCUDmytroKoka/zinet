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

################################################
#
#	Main program
#
################################################

: ${instanceRoot=}

source /etc/default/zinet 2>/dev/null
if [ $? -ne 0 ]; then
	echo "Error reading zinet default runtime"
	exit 1
fi

for f in ${ziNetEtcDir}/*.functions; do source $f; done 2> /dev/null
for f in ${ziNetEtcDir}/*.properties; do source $f; done 2> /dev/null

instID=opendj
opendjCfgDir=${ziNetEtcDir}/opendj
if [ ! -z ${instanceRoot} ]; then
    opendjCfgDir="${opendjCfgDir}/${instanceRoot}"
    instID=${instanceRoot}
fi

for f in ${opendjCfgDir}/*.functions; do
    source $f
    if [ $? -ne 0 ]; then
        echo "Error reading ${f}"
        set +a
        exit 1
    fi
done 2> /dev/null

for f in ${opendjCfgDir}/opendj-*-default.properties; do
    source $f
    if [ $? -ne 0 ]; then
        echo "Error reading ${f}"
        set +a
        exit 1
    fi
done 2> /dev/null

for f in ${opendjCfgDir}/opendj-*-override.properties; do
    source $f
    if [ $? -ne 0 ]; then
        echo "Error reading ${f}"
        set +a
        exit 1
    fi
done 2> /dev/null

DIRMGR_DN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
PASSWORD=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

ADMIN_DN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Admin")
ADMIN_PASSWORD=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Admin")

ADMIN_PORT=${OPENDJ_ADMIN_PORT}
LDAP_PORT=${OPENDJ_LDAP_PORT}
unset OPENDJ_JAVA_ARGS

eval "$@"
