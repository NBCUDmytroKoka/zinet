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

####################################################################
# With no IP to remove (-L) provided explicitly it will be fetched from dsreplication status error output
####################################################################

: ${OPENDJ_HOME_DIR:="/opt/opendj"}
APPLY_CHANGES=0
BAD_DJ_IPS=""

while getopts L:ah option; do
    case "${option}" in
        a) APPLY_CHANGES=1;;
        L) BAD_DJ_IPS=${OPTARG};;
        h) echo "=====================USAGE======================"
           echo "-L  | (optional) IPs to be cleared from replication topology (CSV for multiple IPs)"
           echo "-a  | (optional) Apply changes. If not set script will only detect and output bad IPs"
           echo "With no IP to remove (-L) provided explicitly it will be fetched from dsreplication status error output"
           exit 0;;
        *) echo "Invalid Option: -${option} requires an argument" 1>&2
           exit 2;;
    esac
done

####################################################################
# Functions
####################################################################

####################################################################
# $1 - target DJ IP on which clearing topology
# $2 - Bad DJ IP to be removed from topology
# $3 - domain name 
####################################################################
clear_replication_domain() {
    if [ ${APPLY_CHANGES} = 1 ]; then
        echo Clearing bad IP $2 from $3 replication domain configuration on $1... 
        EXITCODE=0
        ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-domain-prop -h ${1} -D "${DIRMGR_DN}" -p ${ADMIN_PORT} -w ${PASSWORD} --provider-name "Multimaster Synchronization" --domain-name "${3}" --remove replication-server:$2:${OPENDJ_REPL_PORT} --no-prompt --trustall || EXITCODE=$?
    else
        echo "${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-domain-prop -h ${1} -D \"${DIRMGR_DN}\" -p ${ADMIN_PORT} -w <PASSWORD> --provider-name \"Multimaster Synchronization\" --domain-name \"$3\" --remove replication-server:$2:${OPENDJ_REPL_PORT} --no-prompt --trustall"
    fi
}

###################################################################
# $1 - target DJ IP on which clearing topology
# $2 - Bad DJ IP to be removed from topology
###################################################################
clear_replication_server() {
    if [ ${APPLY_CHANGES} = 1 ]; then
        echo Clearing bad IP $2 from replication server configuration on $1...
        EXITCODE=0
        ${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-server-prop -h ${1} -D "${DIRMGR_DN}" -p ${ADMIN_PORT} -w ${PASSWORD} --provider-name "Multimaster Synchronization" --remove replication-server:${2}:${OPENDJ_REPL_PORT} --no-prompt --trustall || EXITCODE=$?
    else
        echo "${OPENDJ_HOME_DIR}/bin/dsconfig set-replication-server-prop -h ${1} -D \"${DIRMGR_DN}\" -p ${ADMIN_PORT} -w <PASSWORD> --provider-name \"Multimaster Synchronization\" --remove replication-server:${2}:${OPENDJ_REPL_PORT} --no-prompt --trustall"
    fi

}

clear_admin_data() {
    if [ ${APPLY_CHANGES} = 1 ]; then
        echo Clearing cn=admin data on ${HOST_IP}
        ldapdelete -h ${HOST_IP} -p ${LDAP_PORT} -D "${DIRMGR_DN}" -w ${PASSWORD} "cn=${1}:${OPENDJ_ADMIN_PORT},cn=Servers,cn=admin data" 
    else
        echo "ldapdelete -h ${HOST_IP} -p ${LDAP_PORT} -D \"${DIRMGR_DN}\" -w <PASSWORD> \"cn=${1}:${OPENDJ_ADMIN_PORT},cn=Servers,cn=admin data\" "
    fi
}

echo Sourcing OpenDJ environment variables
source <(opendj-ops-env.sh set | grep -E "(^PASSWORD|^ADMIN_PASSWORD|^ADMIN_PORT|^HOST_IP|^ADMIN_DN|^DIRMGR_DN|^LDAP_PORT|^OPENDJ_REPL_PORT|^OPENDJ_ADMIN_PORT|^OPENDJ_HOME_DIR)")

if [ -z ${BAD_DJ_IPS} ]; then
    set +o pipefail
    echo Fetching Bad DJ IPs from dsreplication status error output
    BAD_DJ_IPS=$(${OPENDJ_HOME_DIR}/bin/dsreplication status -h ${HOST_IP} -I ${ADMIN_DN} --port ${ADMIN_PORT} -w ${ADMIN_PASSWORD} --no-prompt --trustall 2>&1 > /dev/null | grep "Error on " | grep -o -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" |  sort | uniq )
    set -o pipefail
fi

if [ -z "${BAD_DJ_IPS}" ]; then
    echo Bad DJ IP neither provided in command input nor detected from dsreplication status
    exit 0
fi

for bad_dj_ip in ${BAD_DJ_IPS//,/ }; do
  echo Bad DJ IP: $bad_dj_ip
done

echo Getting IPs in replication topology
TOPOLOGY_DS_IPS=$(${OPENDJ_HOME_DIR}/bin/dsreplication status -h ${HOST_IP} -I ${ADMIN_DN} --port ${ADMIN_PORT} -w ${ADMIN_PASSWORD} --no-prompt --trustall 2>/dev/null | grep -o -E "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | sort | uniq)

if [ -z "${TOPOLOGY_DS_IPS}" ]
then
    echo Error parsing dsreplication status
    exit 1
fi

echo DS IPs in replication topology: 
echo ${TOPOLOGY_DS_IPS}

if [ ${APPLY_CHANGES} = 0 ]; then
    echo Running in dry-run mode
    echo Run following commands to clear replication topology
    echo Or add -a command option to apply changes
fi

###############################################################################
# Iterating on all Bad DJ IPs over all instances in topology
###############################################################################
for bad_dj_ip in ${BAD_DJ_IPS//,/ }; do

  echo Processing bad replication IP: ${bad_dj_ip}
  IN_TOPOLOGY=0

  ###############################################################################
  # Checking whether Bad IP exists in current replication topology
  ###############################################################################
  for target_dj in ${TOPOLOGY_DS_IPS}; do
    if [ ! -z "${bad_dj_ip}" ] && [ "${target_dj}" = "${bad_dj_ip}" ]; then
      echo ${bad_dj_ip} is reported in current replication topology. Not removing it
      IN_TOPOLOGY=1
    fi
  done

  [ ${IN_TOPOLOGY} -eq 1 ] && continue

  for target_dj in ${TOPOLOGY_DS_IPS}; do
    ###############################################################################
    # Clearing replication domains data
    ###############################################################################
    REPLICATION_DOMAINS=$(${OPENDJ_HOME_DIR}/bin/dsconfig list-replication-domains --provider-name "Multimaster Synchronization" -h $target_dj -D "${DIRMGR_DN}" -p ${ADMIN_PORT} -w ${PASSWORD} --trustAll --script-friendly)

    SAVEIFS=$IFS
    IFS=$'\n'

    for domain in ${REPLICATION_DOMAINS}; do
      if [ ! -z "${bad_dj_ip}" ]; then
        clear_replication_domain ${target_dj} ${bad_dj_ip} ${domain}
        clear_replication_server ${target_dj} ${bad_dj_ip}
      fi
    done

    IFS=$SAVEIFS 
    echo
  done
  
  ###############################################################################
  # Clearing cn=admin data
  # cn=admin data replicating to other DJ instances so removing on single host
  ###############################################################################
  clear_admin_data $bad_dj_ip

done