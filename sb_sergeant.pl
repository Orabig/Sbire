#!/usr/bin/perl

####################
#
# sb_sergeant.pl
#
# Version 0.9.7
#
# Historique : 0.9.0 :  First revision
#              0.9.6 :  Config::Simple package is not required anymore
#              0.9.7 :  Fixed @server_list_file selection mode
# 
# Knows about a list of servers, and delegates to sb_master.pl to send them commands in group
#
# Usage : sb_sergeant.pl @server_list_file [--csv] [ -c <COMMAND> args... ]
#      or sb_sergeant.pl alias*            [--csv] [ -c <COMMAND> args... ]
#      or sb_sergeant.pl all               [--csv] [ -c <COMMAND> args... ]
#      or sb_sergeant.pl list
#
# /etc/sb_sergeant.cfg must exist and define SBIRE_LIST path
# 
####################

use strict;

my $CONFIG_FILE = '/opt/adm/sbire-master/etc/sb_sergeant.cfg';

$\=$/;

my $files = shift @ARGV;

# On recherche la presence d'une option --csv dans les arguments
our $CSV = grep /^--csv$/, @ARGV;
@ARGV = grep !/^--csv$/, @ARGV;
undef $\ if $CSV;

defined $files || die ('Usage : sb_sergeant.pl (list | all | alias | @server_list_file) [ -c <COMMAND> args... ]');

my %Config;
open CFG, $CONFIG_FILE || die "Cannot find config file $CONFIG_FILE";
while (<CFG>){chomp;$Config{$1}=$2 if (/\s*(\w+)\s+(.*)/)}
close CFG;

# Loads the configuration
our @SBIRES;
our %SBIRES = &readSbireFile($Config{'SBIRE_LIST'});

if (lc $files eq 'list') {
	# List all sbires
	$,=$\;print grep /\w/, @SBIRES;
	exit(0);
}

my $MULTIPLE = ($files=~/^\@/) || ($files=~/^all$/i);

if ($files=~s/^\@//) {
	# open file list
	open LST, "<$files" || die ("Cannot open $files");	
	map { 
		chomp;
		if (defined $SBIRES{$_}) {
			&process($_);
		} else {
			print "Warning : Sbire unknown : $_";
		}
	} grep /\w/, map {s/(#|;).*//;$_} <LST>;
	close LST;
	exit(0);
	}

# Else
	{
	# filter servers
	$files=~s/\*/.*/g;
	$files=".*" if (lc $files eq 'all');
	map { &process($_) } grep /$files/i, grep /\w/, @SBIRES;
	exit(0);
	}


# ------------------------------------------------

#
#
#
sub process() {
	my ($alias)=@_;
	my %sbire = %{$SBIRES{$alias}};
	my $name=$sbire{'NAME'};
	my $protocol=$sbire{'PROTOCOL'};
	my @args = @ARGV;

	my $cmd;
	my $download = grep /^download$/, @args;

	my $header=""; 
	unless ($CSV) {
		$header="| $alias ($name) |"; 
		my $line="-" x length $header; 
		$header="$line\n$header\n$line";
	} 
	print $header unless ($CSV || $download) && !$MULTIPLE;
	
	# Local (mainly for testing)
	if (uc $protocol eq 'LOCAL') {
		$cmd="./sbire_master.pl -H $name -P $protocol @args";
	}
	
	if (uc $protocol eq 'NRPE') {
		my $use_ssh = &getConf($alias,'NRPE-USE-SSH');
		my $port = &getConf($alias,'NRPE-PORT');
		
		$name.=":$port" if ($port);
		my $sshcmd = $use_ssh ? '' : '-S 1';
		$cmd="./sbire_master.pl -H $name -P $protocol $sshcmd @args";
	}
	
	#print $cmd;
	my $output = `$cmd`;
	if ($CSV) {
		# En sortie CSV, on prefixe toutes les lignes par le nom du serveur son adresse IP et le protocole
		$output=~s/^/$alias\t/gm;
	}
	print $output;
}

sub getConf() {
	my ($alias,$key)=@_;
	my $value=$SBIRES{$alias}{$key};
	$value=$SBIRES{''}{$key} unless defined $value;
	return $value;
}

#
# Reads the config file
#
# The syntax is :
#
# SERVER_ALIAS	SERVER_NAME/IP	PROTOCOL
#
# Lines that starts with a space is an attribute
sub readSbireFile() {
	my ($file)=@_;
	my %CONF;
	my $lastAlias = '';
	open CFG, $file or die('Cannot open $file.');
	while (<CFG>) {
		s/(#|;).*//;
		next unless /\w/;
		if (/^\s+(\S+)\s+(.*)/) {
			# Config attribute
			my $key=$1;
			my $value=$2;
			$CONF{$lastAlias}->{$key}=$value;
		}
		else
		{
			my($alias,$name,$protocol)=split/\s+/;
			$lastAlias=$alias;
			push @SBIRES,$alias;
			$CONF{$alias}->{'NAME'}=$name;
			$CONF{$alias}->{'PROTOCOL'}=$protocol;
		}
	}
	%CONF;
}

