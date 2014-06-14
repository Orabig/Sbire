#!/bin/sh

_sbire_master_path=/opt/sbire
_git_raw_base_url=https://raw.githubusercontent.com/Orabig/Sbire/master

log()  { printf "%b\n" "$*"; }
debug(){ [[ ${rvm_debug_flag:-0} -eq 0 ]] || printf "Running($#): $*"; }
fail() { log "\nERROR: $*\n" ; exit 1 ; }

mkdir -p ${_sbire_master_path}/etc
curl -sSL ${_git_raw_base_url}/sb_sergeant.pl > ${_sbire_master_path}/sb_sergeant.pl
curl -sSL ${_git_raw_base_url}/sbire_master.pl > ${_sbire_master_path}/sbire_master.pl
touch ${_sbire_master_path}/etc/server_list.txt

curl -sSL ${_git_raw_base_url}/etc/bash_aliases.sample | sed "s:/opt/Sbire/:${_sbire_master_path}/:" | sed "s:perl:$(which perl):" > /etc/profile.d/sbire_aliases
. /etc/profile.d/sbire_aliases

log "SUCCESS : Sbire has been installed."
