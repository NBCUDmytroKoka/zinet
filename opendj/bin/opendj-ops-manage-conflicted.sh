#!/bin/bash

################################################
#   Copyright (c) 2015-18 zibernetics, Inc.
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#   
#       http://www.apache.org/licenses/LICENSE-2.0
#   
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
################################################

SCRIPT=$(readlink -f $0)
SCRIPTPATH=$(dirname ${SCRIPT})
DIRNAME=$(basename ${SCRIPTPATH})

: ${instanceRoot=}
localTargetHostList=$(hostname -s)
localIsDryRun=false
localApplyChanges=false
localCheckOnly=true
localBaseDNs=

USAGE=" Usage: `basename $0` -b localBaseDNs [ -I instanceRoot ] [ -n localTargetHostList=$(hostname) ] [ -d (dryrun=false) ] [ -c (localCheckOnly=true )] [ -a (localApplyChanges=false) ]"

while getopts hb:I:n:dca OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        b)
            localBaseDNs="$OPTARG"
            ;;
        I)
            instanceRoot="$OPTARG"
            ;;
        n)
            localTargetHostList="$OPTARG"
            ;;
        d)
            localIsDryRun=true
            localApplyChanges=false
            localCheckOnly=false
            ;;
        c)
            localCheckOnly=true
            localIsDryRun=false
            localApplyChanges=false
            ;;
        a)
            localApplyChanges=true
            localIsDryRun=false
            localCheckOnly=false
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

if [ -z "${localBaseDNs}" ]; then
    echo "Must pass a localBaseDNs"
    echo $USAGE >&2
    cd ${SAVE_DIR}
    exit 1
fi

##################################################
#
# Main program
#
##################################################

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

localLDAPBindDN=$(netrcGetLogin ${opendjCfgDir}/.netrc "OpenDJ_Root")
localLDAPBindPW=$(netrcGetPasswd ${opendjCfgDir}/.netrc "OpenDJ_Root")

if [[ $(id -un) != "${ziAdmin}" ]]; then
    echo "This script must be run as ${ziAdmin}."
    exit 1
fi

for baseDN in "${localBaseDNs}"; do

    IFS=',' read -ra hostArr <<< "${localTargetHostList}"
    for hostIP in "${hostArr[@]}"; do

        if [ "${localCheckOnly}" == true ]; then
            echo "#### Checking for conflicts - hostIP: ${hostIP}, baseDN: $baseDN"
            ${OPENDJ_HOME_DIR}/bin/ldapsearch   \
            --bindDN "${localLDAPBindDN}"       \
            --bindPassword "${localLDAPBindPW}" \
            --hostname ${hostIP}                \
            --port ${OPENDJ_LDAP_PORT}          \
            --trustAll                          \
            --baseDN "${baseDN}"                \
            "(ds-sync-conflict=*)" ds-sync-conflict \* +
            echo
        else
            echo "#### Checking for conflicts - hostIP: ${hostIP}, baseDN: $baseDN"
            conflictedEntries=$(${OPENDJ_HOME_DIR}/bin/ldapsearch \
            --bindDN "${localLDAPBindDN}"       \
            --bindPassword "${localLDAPBindPW}" \
            --hostname ${hostIP}                \
            --port ${OPENDJ_LDAP_PORT}          \
            --trustAll                          \
            --baseDN "${baseDN}"                \
            "(ds-sync-conflict=*)" 1.1 | sed '/^\s*$/d' | awk '{ print $2 }')

            if [ -n "${conflictedEntries}" ]; then
                while read -r conflictedEntry || [[ -n "${conflictedEntry}" ]]; do
                    echo "#### Processing conflicted entry - hostIP: $hostIP, baseDN: $baseDN, conflictedEntry: '$conflictedEntry'"
                    if [ "${localIsDryRun}" == true ]; then
                        echo ${OPENDJ_HOME_DIR}/bin/ldapdelete \
                        --bindDN "${localLDAPBindDN}"       \
                        --bindPassword "${localLDAPBindPW}" \
                        --hostname ${hostIP}                \
                        --port ${OPENDJ_LDAP_PORT}          \
                        --trustAll                          \
                        "${conflictedEntry}"                
                    else
                        ${OPENDJ_HOME_DIR}/bin/ldapdelete   \
                        --bindDN "${localLDAPBindDN}"       \
                        --bindPassword "${localLDAPBindPW}" \
                        --hostname ${hostIP}                \
                        --port ${OPENDJ_LDAP_PORT}          \
                        --trustAll                          \
                        "${conflictedEntry}"                
                    fi
                done <<< "${conflictedEntries}"
            fi
        fi
    done
done
