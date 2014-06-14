#!/bin/sh

_sbirepath=/opt/sbire
_sbire=${_sbirepath}/sbire.pl
_sbire_raw_url=https://raw.githubusercontent.com/Orabig/Sbire/master/server_side/sbire.pl
_sbire_cfg=/etc/sbire.cfg

log()  { printf "%b\n" "$*"; }
debug(){ [[ ${rvm_debug_flag:-0} -eq 0 ]] || printf "Running($#): $*"; }
fail() { log "\nERROR: $*\n" ; exit 1 ; }

\which which >/dev/null 2>&1 || fail "Could not find 'which' command, make sure it's available first before continuing installation."
\which curl  >/dev/null 2>&1 || fail "Could not find 'curl' command, make sure it's available first before continuing installation."
\which sed   >/dev/null 2>&1 || fail "Could not find 'sed' command, make sure it's available first before continuing installation."
\which awk   >/dev/null 2>&1 || fail "Could not find 'awk' command, make sure it's available first before continuing installation."
\which perl  >/dev/null 2>&1 || fail "Could not find 'perl' command, make sure it's available first before continuing installation."

_perl=$(\which perl)

_nrpeps=$(ps -ef | grep nrpe | grep -v grep)
_nrpecfg=$(echo ${_nrpeps} | sed 's/.* -c \(.[^ \t]*\).*/\1/' | sed 's/.*[ \t].*//')
_nrpeuser=$(echo ${_nrpeps} | awk '{print $1}')
_nrpepid=$(echo ${_nrpeps} | awk '{print $2}')

if [[ -z "${_nrpecfg}" ]]
then
	# Tenter d'installer nrpe en automatique (apt-get)
	if  \which apt-get >/dev/null 2>&1 
	then
	  log "You can install NRPE with :"
	  log "apt-get install nagios-nrpe-server"
	fi
	fail "Could not find NRPE config file. Is NRPE installed and running ?"
fi

# Check pour relancer le service NRPE
if  \which systemctl >/dev/null 2>&1 
then
	_nrpe_service=$(systemctl | grep nrpe | awk '{print $1}')

	# Check if the PID is correct
	_check_pid=$(systemctl status ${_nrpe_service} | grep "PID\W\+${_nrpepid}\b" | wc -l)
	if [[ ${_check_pid} == "0" ]]; then fail "NRPE service PID does not match PID found in process (${_nrpepid})"; fi
elif \which service >/dev/null 2>&1
then
	_nrpe_service=$(ls /etc/init.d | grep nrpe | awk '{print $1}')

	# Check if the PID is correct
	_check_pid=$(cat /var/run/nagios/nrpe.pid | grep "\b${_nrpepid}\b" | wc -l)
	if [[ ${_check_pid} == "0" ]]; then fail "NRPE service PID does not match PID found in process (${_nrpepid})"; fi
else
	fail "Could not find how to restart service. This installer only supports 'service' or 'systemctl' at this time."
fi

_check_sbire=$(grep sbire ${_nrpecfg} | wc -l)
if [[ "${_check_sbire}" != "0" ]]; then fail "Sbire seems to be already installed in ${_nrpecfg}"; fi

# Técharge sbire
log Downloading sbire.pl to ${_sbirepath}...
mkdir -p "${_sbirepath}"
curl -sSL ${_sbire_raw_url} > ${_sbire} || fail "Error while downloading. Do you have network access ?"
chown ${_nrpeuser} ${_sbire}

# Ajoute la ligne de commande vers sbire àrpe.cfg
log "Modifying configuration to ${_nrpecfg}... (dont_blame_nrpe must be set)"
mv --force ${_nrpecfg} ${_nrpecfg}.old
cat ${_nrpecfg}.old | sed 's/^\(dont_blame_nrpe\)=.*/\1=1/' > ${_nrpecfg}
echo "command[sbire]=${_perl} ${_sbire} ${_sbire_cfg} \$ARG1\$ \$ARG2\$ \$ARG3\$ \$ARG4\$ \$ARG5\$ \$ARG6\$ \$ARG7\$ \$ARG8\$ \$ARG9\$" >> ${_nrpecfg}

mv 

# Creation du fichier sbire.cfg
touch ${_sbire_cfg}
chown ${_nrpeuser} ${_sbire_cfg}

# Relance du service NRPE
if  \which systemctl >/dev/null 2>&1 
then
	log Restarting ${_nrpe_service}...
	systemctl restart ${_nrpe_service}
elif  \which service >/dev/null 2>&1 
then
	log Restarting ${_nrpe_service}...
	service ${_nrpe_service} restart
fi

log "SUCCESS : Sbire has been added to NRPE configuration"
