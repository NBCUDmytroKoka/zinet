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

# if [[ $(id -un) != root ]]; then
# 		echo "#### This script must be run as root."
# 		exit 0
# fi

javaRootDir=/usr/lib/jvm
jdkTarball=
# Options
#  *  default-jre-headless
#     oracle-java6-installer
#     oracle-java7-installer
#     oracle-java8-installer
#     openjdk-8-jdk
#     etc...
    
javaInstallPackage=default-jre-headless

USAGE="	Usage: `basename $0` [ -j jdkTarball | -J javaInstallPackage (default-jre-headless) ] [ -p javaRootDir=$javaRootDir ]"

while getopts hj:J:p: OPT; do
    case "$OPT" in
        h)
            echo $USAGE
            exit 0
            ;;
        j)
            jdkTarball="$OPTARG"
            javaInstallPackage=
            ;;
        J)
            javaInstallPackage="$OPTARG"
            jdkTarball=
            ;;
        p)
            javaRootDir="$OPTARG"
            ;;
        \?)
            # getopts issues an error message
            echo $USAGE >&2
            exit 1
            ;;
    esac
done

################################################
#
#	Main program
#
################################################

echo "#### Installing Java runtime"

# echo "#### loading ziNet - $SCRIPT"
# source /etc/default/zinet 2>/dev/null
# if [ $? -ne 0 ]; then
# 	echo "Error reading zinet default runtime"
# 	exit 1
# fi
# 
# if [[ $(id -un) != ${ziPKIAdmin} ]]; then
#     echo "#### This script must be run as ${ziPKIAdmin}."
#     cd ${SAVE_DIR}
#     exit 1
# fi

if [ ! -z "${javaInstallPackage}" ]; then

    isOracle=$(grep "oracle" <<< "${javaInstallPackage}" >/dev/null 2>&1 && echo true || echo false)
    if ${isOracle}; then
        echo "#### Oracle installation - adding PPA"
        add-apt-repository ppa:webupd8team/java -y
        echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
        echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections
    fi
    
    echo "#### Running package installation for ${javaInstallPackage}"
    [ ! -d ${javaRootDir} ] && mkdir -p ${javaRootDir}

    $(which apt-get) && apt-get update -y && apt-get install -y "${javaInstallPackage}" || yum update -y && yum install -y "${javaInstallPackage}"
    if [ "$?" -ne 0 ]; then 
        echo "#### Error installing ${javaInstallPackage}"
        exit 1
    fi

    echo "#### Setting up runtime - pkg install"
    JAVA_HOME=${javaRootDir}/$(ls -d -t ${javaRootDir}/* | head -1)
    echo "export JAVA_HOME=${JAVA_HOME}" > /etc/profile.d/java.sh
    chmod +x /etc/profile.d/java.sh

elif [ ! -z "${jdkTarball}" ]; then

    echo "#### Installing Oracle Java - tarball"
    [ ! -d ${javaRootDir} ] && mkdir -p ${javaRootDir}
    tar zxvf ${jdkTarball} -C ${javaRootDir}
    if [ "$?" -ne 0 ]; then 
        echo "#### Error installing ${jdkTarball}"
        exit 1
    fi

    echo "#### Setting up runtime"
    JAVA_HOME=${javaRootDir}/$(tar tzf "${jdkTarball}" | head -1 | awk -F/ '{ print $1 }')
    echo "export JAVA_HOME=${JAVA_HOME}" > /etc/profile.d/java.sh
    chmod +x /etc/profile.d/java.sh

    if [[ $(id -un) == root ]]; then
        echo "#### Setting alternatives"
        update-alternatives --install "/usr/bin/java" "java" "${JAVA_HOME}/bin/java" 1
        update-alternatives --install "/usr/bin/javac" "javac" "${JAVA_HOME}/bin/javac" 1
        update-alternatives --install "/usr/bin/javaws" "javaws" "${JAVA_HOME}/bin/javaws" 1
        update-alternatives --install "/usr/bin/keytool" "keytool" "${JAVA_HOME}/bin/keytool" 1
        update-alternatives --install "/usr/bin/jar" "jar" "${JAVA_HOME}/bin/jar" 1
    fi

else

    echo "#### Configuration error jdkTarball and javaInstallPackage are undefined"
    exit 1
    
fi

echo "#### Java installed"
