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

ziD=zinet
ziNetEtcDir=/etc/${ziD}
ziAdmin=zig
ziAdminGrp=zig
localHostName=
localStorageDevice=
localStorageMount=
localSearchDomains=

USAGE="	Usage: `basename $0` [ -z ziD=$ziD ] [ -Z ziNetEtcDir=$ziNetEtcDir ] [ -u ziAdmin=$ziAdmin ] [ -U ziAdminGroup=$ziAdminGrp ] [ -n hostName=$(hostname) ] [ -d storageDevice ] [ -m mountPoint ] [ -r Search Domains ]"

while getopts hz:Z:u:U::n:d:m:r: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        z)
            ziD="$OPTARG"
            ;;
        Z)
            ziNetEtcDir="$OPTARG"
            ;;
        u)
            ziAdmin="$OPTARG"
            ;;
        U)
            ziAdminGrp="$OPTARG"
            ;;            
        n)
            localHostName="$OPTARG"
            ;;
        d)
            localStorageDevice="$OPTARG"
            ;;
        m)
            localStorageMount="$OPTARG"
            ;;
        r)
            localSearchDomains="$OPTARG"
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

if [ -z "${ziD}" ] || [ -z "${ziNetEtcDir}" ]; then
	echo "Must pass a valid ziD and ziNetEtcDir"
    echo $USAGE >&2
    exit 1
fi

if [ "${ziAdmin}" != "zig" ] && [ "${ziAdminGrp}" == "zig" ]; then
    ziAdminGrp=${ziAdmin}
fi

BACKOUT_DATE=$(date +%Y%m%d-%H%M%S)

isIP=$(echo "${localHostName}" |  grep -Eo "([0-9]{1,3}[\.]){3}[0-9]{1,3}")
if [ ! -z "${localHostName}" ] && [ -z "${isIP}" ]; then
    if [[ $(id -un) != root ]]; then
        echo "#### This script must be run as root to change system settings."
        exit 1
    fi

    echo "#### Setting host name to: ${localHostName}"
    echo ${localHostName} > /etc/hostname
    hostname ${localHostName}
    cp /etc/hosts /etc/hosts.${BACKOUT_DATE}
    sed -i "s|^[ \t#]*\(127.0.0.1\)[ \t]*.*|\1 localhost $(hostname -s) $(hostname)|g" /etc/hosts
fi

if [ ! -z "${localSearchDomains}" ]; then
    if [[ $(id -un) != root ]]; then
        echo "#### This script must be run as root to change system settings."
        exit 1
    fi

    echo "#### Setting search domain(s) to: ${localSearchDomains}"
    cp /etc/resolvconf/resolv.conf.d/base /etc/resolvconf/resolv.conf.d/base.${BACKOUT_DATE}
    echo "search ${localSearchDomains}" >> /etc/resolvconf/resolv.conf.d/base
    resolvconf -u
fi

# check and see if the file system already exists. If not, create it
if [ ! -z "${localStorageDevice}" ] && [ ! -z "${localStorageMount}" ]; then
    if [[ $(id -un) != root ]]; then
        echo "#### This script must be run as root to change system settings."
        exit 1
    fi

    echo "#### Preparing file system"
    mkfs -F -t ext4 ${localStorageDevice}
    mkdir -p ${localStorageMount}
    mount ${localStorageDevice} ${localStorageMount}
    cp /etc/fstab /etc/fstab.${BACKOUT_DATE}
    echo "${localStorageDevice}       ${localStorageMount}   ext4    defaults,nofail        0 2" >> /etc/fstab
fi

echo "#### Creating /etc/default/zinet"
echo "ziD=\"${ziD}\"" > /etc/default/zinet
echo "ziNetEtcDir=\"${ziNetEtcDir}\"" >> /etc/default/zinet
echo "ziAdmin=\"${ziAdmin}\"" >> /etc/default/zinet
echo "ziAdminGrp=\"${ziAdminGrp}\"" >> /etc/default/zinet
if [[ $(id -un) == root ]]; then
    chmod 644 /etc/default/zinet
fi

if [ ! -z "${localStorageMount}" ] && [ -d "${localStorageMount}" ]; then
	echo "#### Creating ${ziNetEtcDir} symlink (${localStorageMount}/etc)"
	mkdir -p ${localStorageMount}/etc
	[ "${localStorageMount}/etc" != "${ziNetEtcDir}" ] && ln -sf ${localStorageMount}/etc ${ziNetEtcDir}
else
    echo "#### Creating ${ziNetEtcDir}"
	mkdir -p ${ziNetEtcDir}
fi

if [ -z "$(getent group ${ziAdminGrp} 2>/dev/null)" ]; then
    if [[ $(id -un) != root ]]; then
        echo "#### This script must be run as root to change system settings."
        exit 1
    fi

    echo "#### Adding administrative group $ziAdminGrp"
    groupadd ${ziAdminGrp}
fi

if [ -z "$(getent passwd ${ziAdmin} 2>/dev/null)" ]; then
    if [[ $(id -un) != root ]]; then
        echo "#### This script must be run as root to change system settings."
        exit 1
    fi

    echo "#### Adding administrative user $ziAdmin"
    useradd -s /bin/false -g ${ziAdminGrp} ${ziAdmin}
fi

echo "#### Copying common functions to ${ziNetEtcDir}"
cp ${SCRIPTPATH}/*.functions ${ziNetEtcDir}/

if [[ $(id -un) == root ]]; then
    chown -R ${ziAdmin}:${ziAdminGrp} ${ziNetEtcDir}
fi

echo "#### Done. The zinet core module is now ready."

cd ${SAVE_DIR}

