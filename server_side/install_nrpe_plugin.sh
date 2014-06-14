#!/bin/sh

_latest_nrpe_version=2.15
_nrpe_tar_gz=nrpe-${_latest_nrpe_version}.tar.gz
_nrpe_src_dir=nrpe-${_latest_nrpe_version}
_install_dir=/opt
_nrpe_bin=/usr/bin/check_nrpe

_nrpe_url=http://downloads.sourceforge.net/project/nagios/nrpe-2.x/nrpe-${_latest_nrpe_version}/nrpe-${_latest_nrpe_version}.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fnagios%2Ffiles%2Fnrpe-2.x%2Fnrpe-${_latest_nrpe_version}%2F\&ts=$(date +%s)\&use_mirror=softlayer-ams

log()  { printf "%b\n" "$*"; }
debug(){ [[ ${rvm_debug_flag:-0} -eq 0 ]] || printf "Running($#): $*"; }
fail() { log "\nERROR: $*\n" ; exit 1 ; }

\which tar >/dev/null 2>&1 || fail "Could not find 'tar' command, make sure it's available first before continuing installation."
\which curl  >/dev/null 2>&1 || fail "Could not find 'curl' command, make sure it's available first before continuing installation."
\which sed   >/dev/null 2>&1 || fail "Could not find 'sed' command, make sure it's available first before continuing installation."

apt-get update
apt-get install build-essential libssl-dev

_lib_ssl=$(dpkg -S libssl | grep libssl-dev | grep libssl.so | sed 's/.* \(.*\)\/libssl\.so.*/\1/')

curl -sSL ${_nrpe_url} > ${_install_dir}/${_nrpe_tar_gz}
cd ${_install_dir}
tar xvfz ${_nrpe_tar_gz}
if [[ ! -d ${_install_dir}/${_nrpe_src_dir} ]]
then
	fail "Could not create installation directory"
else
	rm -f ${_nrpe_tar_gz}
fi

cd ${_install_dir}/${_nrpe_src_dir}
./configure --enable-command-args --with-ssl-lib=${_lib_ssl} --libexecdir=/usr/bin
make all
make install-plugin

if [[ -f ${_nrpe_bin} ]]
then
	log "${_nrpe_bin} installed"
	rm -fr ${_install_dir}/${_nrpe_src_dir}
else
	fail "${_nrpe_bin} not found. Install failed"
fi
