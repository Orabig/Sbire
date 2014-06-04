#!/usr/bin/perl

my $Version= 'Version 0.9.17';

####################
#
# sb_sergeant.pl
#
# Historique : 0.9.0 :  First revision
#              0.9.6 :  Config::Simple package is not required anymore
#              0.9.7 :  Fixed @server_list_file selection mode
#              0.9.8 :  Some fix
#              0.9.9 :  The script can now invoke sbire_master from another directory
#              0.9.10:  Changed the @server_list_file behaviour
#              0.9.11:  The server must now be fully named by the user (autocompletion was a bad idea)
#              0.9.12:  Added SSH support
#              0.9.13:  Fixed output on empty result with CSV option
#              0.9.14:  Default configuration when sb_sergeant.cfg does not exist
#              0.9.15:  Added the optional -d <dir> argument to run command
#              0.9.16:  The server_list file can now contain characters after the server name/IP
#              0.9.17:  __NAME__ and __TARGET__ may now be used in all commands
# 
# Knows about a list of servers, and delegates to sb_master.pl to send them commands in group
#
# Usage : sb_sergeant.pl @server_list_file [--csv] [ -c <COMMAND> args... ]
#      or sb_sergeant.pl alias*            [--csv] [ -c <COMMAND> args... ]
#      or sb_sergeant.pl all               [--csv] [ -c <COMMAND> args... ]
#      or sb_sergeant.pl list
#      or sb_sergeant.pl ......            --local <COMMANDS>   (use __ALIAS__ to get the target server name, and __TARGET__ to get the IP)
#
# /etc/sb_sergeant.cfg must exist and define SBIRE_LIST path
# 
####################

use strict;

my $ROOT_DIR = $0;$ROOT_DIR=~s!/[^/]*$!!;
my $CONFIG_DIR = "$ROOT_DIR/etc";
$CONFIG_DIR = "/etc" if (-f "/etc/sb_sergeant.cfg" && ! -f "$CONFIG_DIR/sb_sergeant.cfg");
my $CONFIG_FILE = "$CONFIG_DIR/sb_sergeant.cfg";

my $MASTER = "$ROOT_DIR/sbire_master.pl";

$\=$/;

my $files = shift @ARGV;

# On recherche la presence d'une option --csv dans les arguments
our $CSV = grep /^--csv$/, @ARGV;
@ARGV = grep !/^--csv$/, @ARGV;
# On recherche la presence d'une option --local dans les arguments
our $LOCAL = grep /^--local$/, @ARGV;
@ARGV = grep !/^--local$/, @ARGV;

undef $\ if $CSV;

defined $files || &usage();
&usage() if $files=~/^--?h/;

my %Config;
if (-f $CONFIG_FILE) {
	open CFG, $CONFIG_FILE;
	while (<CFG>){chomp;$Config{$1}=$2 if (/\s*(\w+)\s+(.*)/)}
	close CFG;
} else {
    # default configuration
	$Config{'SBIRE_LIST'} = "$ROOT_DIR/etc/server_list.txt";
	
}

# Loads the configuration
our @SBIRES;
our %SBIRES = &readSbireFile($Config{'SBIRE_LIST'});

if (lc $files eq 'list') {
	# List all sbires
	$,=$\;print grep /\w/, @SBIRES;
	exit(0);
}

my $MULTIPLE = ($files=~/^\@/) || ($files=~/^all$/i);

$MULTIPLE=0 if $LOCAL && !/__(NAME|TARGET)__/; # Only one iteration if file=='all' but the command is local and no MACRO is used

if ($MULTIPLE && $files=~s/^\@//) {
	# open file list
	-f "$CONFIG_DIR/$files.lst" || die ("$CONFIG_DIR/$files.lst not found");	
	open LST, "$CONFIG_DIR/$files.lst";
	map { 
		chomp;
		if (defined $SBIRES{$_}) {
			&process($_);
		} else {
			print "$_\tServer not found in server list\n";
		}
	} grep /\w/, map {s/[#; ].*//;$_} <LST>;
	close LST;
	exit(0);
	}

# Else
	{
	# filter servers
	my $ifiles = $files;
	$files=~s/\*/.*/g;
	$files=".*" if (lc $files eq 'all');
	my @slist = grep /^$files$/i, grep /\w/, @SBIRES;
	print "$ifiles\tServer not found in server list" unless @slist;
	map { 
		&process($_);
		last unless $MULTIPLE;
		} @slist;
	exit(0);
	}


# ------------------------------------------------

sub usage() {
	print "Sbire_Sergeant : $Version";
	print 'Usage : sb_sergeant.pl list';
	print '        sb_sergeant.pl <SERVER_NAME> [--csv] [--local] [ -c <COMMAND> args... ]';
	print '        sb_sergeant.pl @<LIST_FILE>  [--csv] [--local] [ -c <COMMAND> args... ]';
	print '        sb_sergeant.pl    all        [--csv] [--local] [ -c <COMMAND> args... ]';
	print "Commands : ";
	print "   -c upload   -f <local_file> -n <filename> ";
	print "   -c download -n <filename> [-f <local_file>]";
	print "   -c run [-d <dir>] -- <cmdline>";
	print "   -c config -- <name> <value>";
	print "   -c options";
	print "   -c info [ -n <plugin_path> ]";
	print "   -c restart";
	exit(1);
}
#
#
#
sub process() {
	my ($alias)=@_;
	my %sbire = %{$SBIRES{$alias}};
	my $name=$sbire{'NAME'};
	my $protocol=$sbire{'PROTOCOL'};
	my @args = @ARGV;

	# TODO : This should be rewritten
	my $command = lc(join '%',@args); $command=~s/(^|.*\%)-c\%([^\%]+)(\%.*|$)/$2/;

	my $cmd;
	if ($LOCAL) {
		# This is a local command (master and sbire are not used)
		
		# For now, only 2 commands are supported : run and info
		if ($command eq 'run') {
			$cmd = join " ",@args; 
			unless ($cmd=~s/.*--//) {
				print "ERROR : No command defined";return;
			}
			# It is much more easy to print the command line to understand what is going on...
			print "LOCAL> $cmd";
		} elsif ($command eq 'info') {
			# TODO : This must be rewritten
		    my $file = join '%',@args; $file=~s/(^|.*\%)-n\%([^\%]+)(\%.*|$)/$2/;
			# TODO : this could be better of course.
			my $sbire_path = $0; $sbire_path=~s/sb_sergeant/server_side\/sbire/;
			$cmd="/usr/bin/perl $sbire_path --direct info $file";
		} else {
			print "ERROR : $command is not available with --local option.";return;
		}
			
	} else {	
		# Local protocol (mainly for testing : not very useful to use sbire to run local commands)
		my $header=""; 
		unless ($CSV) {
			$header="| $alias ($name) |"; 
			my $line="-" x length $header; 
			$header="$line\n$header\n$line";
		} 
		print $header unless ($CSV || $command eq 'download') && !$MULTIPLE;
		
		if (uc $protocol eq 'LOCAL') {
			$cmd="$MASTER -H $name -P $protocol @args";
		}
		
		elsif (uc $protocol eq 'NRPE') {
			my $use_ssl = &getConf($alias,'NRPE-USE-SSL');
			my $port = &getConf($alias,'NRPE-PORT');
			
			$name.=":$port" if ($port);
			my $sslcmd = $use_ssl ? '' : '-S 1'; # If NRPE-USE-SSL 0 in server_list, then -S 1 is passed to master (will add -n option to nrpe)
			$cmd="$MASTER -H $name -P $protocol $sslcmd @args";
		}
		
		elsif (uc $protocol eq 'SSH') {
			my $sshpath = &getConf($alias,'SSH-SBIRE-PATH');
			my $sshcfg = &getConf($alias,'SSH-SBIRE-CFG'); 
			shift @args;
			$cmd=qq!$MASTER -H $name -P $protocol -p "$sshpath $sshcfg" @args!;
		}
		
		else {
			# TODO : Warn the user that his configuration is incorrect (unknown protocol)
		}
	}
	$cmd=~s/__NAME__/$alias/g;
	$cmd=~s/__TARGET__/$name/g;
	
	#print $cmd;
	my $output = `$cmd`;
	if ($?) {
		print "ERROR : $!\n$output";
		return;
		}
	if ($CSV && ! $LOCAL) {
		# With CSV output, each line must be prefixed by the server's name
		$output="\n" if $output eq '';
		my $len=length $alias;
		my $max = 20; # TODO : Could change 20 with the largest width
		$len=$max if $len>$max;
		my $prefix = $alias . ' ' x (20 - $len); 
		$output=~s/^/$prefix/gm;
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
	open CFG, $file or die("Cannot open $file.");
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

