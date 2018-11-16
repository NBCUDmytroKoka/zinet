#!/bin/bash

# Exit on error. Append "|| true" if you expect an error.
# We don't want to exit on errors, we will force exits where needed
set -o errexit
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Turn on traces, useful while debugging but commented out by default
#set -o xtrace

APPLY_CHANGES=0
BAD_DJ_IP=""

while getopts L:ah option; do
    case "${option}" in
        a) APPLY_CHANGES=1;;
        L) BAD_DJ_IP=${OPTARG};;
        h) echo "=====================USAGE======================"
           echo "-L  | IP to be cleared from replication topology"
           echo "-a  | Apply changes. If not set script will only detect and output bad IPs"
           exit 0;;
        *) echo "Invalid Option: -${option} requires an argument" 1>&2
           exit 2;;
    esac
done

####################################################################
# Functions
####################################################################

###################################################################
# $1 - target DJ IP on which clearing topology
# $2 - Bad DJ IP to be removed from topology
# $3 - domain name 
##################################################################
clear_replication_domain() {
    if [ ${APPLY_CHANGES} = 1 ]; then
        echo Clearing replication domain $3 from $1... 
        EXITCODE=0
        /opt/opendj/bin/dsconfig set-replication-domain-prop -h ${1} -D "${DIRMGR_DN}" -p ${ADMIN_PORT} -w ${PASSWORD} --provider-name "Multimaster Synchronization" --domain-name "${3}" --remove replication-server:$2:${OPENDJ_REPL_PORT} --no-prompt --trustall || EXITCODE=$?
    else
        echo "/opt/opendj/bin/dsconfig set-replication-domain-prop -h ${1} -D \"${DIRMGR_DN}\" -p ${ADMIN_PORT} -w <PASSWORD> --provider-name \"Multimaster Synchronization\" --domain-name \"$3\" --remove replication-server:$2:${OPENDJ_REPL_PORT} --no-prompt --trustall"
    fi
}

###################################################################
# $1 - target DJ IP on which clearing topology
# $2 - Bad DJ IP to be removed from topology
##################################################################
clear_replication_server() {
    if [ ${APPLY_CHANGES} = 1 ]; then
        echo Clearing replication server $2 from $1...
        EXITCODE=0
        /opt/opendj/bin/dsconfig set-replication-server-prop -h ${1} -D "${DIRMGR_DN}" -p ${ADMIN_PORT} -w ${PASSWORD} --provider-name "Multimaster Synchronization" --remove replication-server:${2}:${OPENDJ_REPL_PORT} --no-prompt --trustall || EXITCODE=$?
    else
        echo "/opt/opendj/bin/dsconfig set-replication-server-prop -h ${1} -D \"${DIRMGR_DN}\" -p ${ADMIN_PORT} -w <PASSWORD> --provider-name \"Multimaster Synchronization\" --remove replication-server:${2}:${OPENDJ_REPL_PORT} --no-prompt --trustall"
    fi

}

clear_admin_data() {
    if [ ${APPLY_CHANGES} = 1 ]; then
        echo Clearing cn=admin data on $1
        ldapdelete -h ${HOST_IP} -p ${LDAP_PORT} -D "${DIRMGR_DN}" -w ${PASSWORD} "cn=${1}:${OPENDJ_ADMIN_PORT},cn=Servers,cn=admin data" 
    else
        echo "ldapdelete -h ${HOST_IP} -p ${LDAP_PORT} -D \"${DIRMGR_DN}\" -w <PASSWORD> \"cn=${1}:${OPENDJ_ADMIN_PORT},cn=Servers,cn=admin data\" "
    fi
}

echo Sourcing OpenDJ environment variables
source <(opendj-ops-env.sh set | grep -E "(PASSWORD|ADMIN_PASSWORD|ADMIN_PORT|HOST_IP|ADMIN_DN|DIRMGR_DN|LDAP_PORT|OPENDJ_REPL_PORT)")

if [ -z ${BAD_DJ_IP} ]; then
    set +o pipefail
    echo Fetching Bad DJ ip from dsreplication status error output
    BAD_DJ_IP=$(/opt/opendj/bin/dsreplication status -h ${HOST_IP} -I ${ADMIN_DN} --port ${ADMIN_PORT} -w ${ADMIN_PASSWORD} --no-prompt --trustall 2>&1 > /dev/null | grep "Error on " | grep -o -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | head -1)
    set -o pipefail
fi

if [ -z ${BAD_DJ_IP} ]; then
    echo Bad DJ IP neither provided in command input nor detected from dsreplication status
    exit 0
fi

echo Getting IPs in replication topology
TOPOLOGY_DS_IPS=$(/opt/opendj/bin/dsreplication status -h ${HOST_IP} -I ${ADMIN_DN} --port ${ADMIN_PORT} -w ${ADMIN_PASSWORD} --no-prompt --trustall 2>/dev/null | grep -o -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | sort | uniq)

if [ -z "${TOPOLOGY_DS_IPS}" ]
then
    echo Error parsing dsreplication status
    exit 1
fi

echo DS IPs in replication topology:
for dj in ${TOPOLOGY_DS_IPS}; do
    echo $dj
    if [ ! -z "${BAD_DJ_IP}" ] && [ "${dj}" = "${BAD_DJ_IP}" ]; then
        echo ${BAD_DJ_IP} is reported in current replication topology. Not removing it
        exit 2
    fi
done

echo Bad replication IP: ${BAD_DJ_IP}

if [ ${APPLY_CHANGES} = 0 ]; then
    echo Running in dry-run mode
    echo Run following commands to clear replication topology
    echo Or add -a command option to apply changes
fi

###############################################################################
# Clearing replication domains data
###############################################################################

for target_dj in ${TOPOLOGY_DS_IPS}; do
    REPLICATION_DOMAINS=$(/opt/opendj/bin/dsconfig list-replication-domains --provider-name "Multimaster Synchronization" -h $target_dj -D "${DIRMGR_DN}" -p ${ADMIN_PORT} -w ${PASSWORD} --trustAll --script-friendly)

    SAVEIFS=$IFS
    IFS=$'\n'

    for domain in ${REPLICATION_DOMAINS}; do
        if [ ! -z "${BAD_DJ_IP}" ]; then
            clear_replication_domain ${target_dj} ${BAD_DJ_IP} ${domain}
            clear_replication_server ${target_dj} ${BAD_DJ_IP}
        fi
    done
done


###############################################################################
# Clearing cn=admin data
# cn=admin data replicating to other DJ instances so removing on single host
###############################################################################

clear_admin_data $BAD_DJ_IP

IFS=$SAVEIFS
