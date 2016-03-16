#!/usr/bin/perl

####################
#
# sb_sergeant.pl
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
# On recherche la presence d'une option --report dans les arguments
our $REPORT = grep /^--report$/, @ARGV;
@ARGV = grep !/^--report$/, @ARGV;
our @REPORT;
# On recherche la presence d'une option --local dans les arguments
our $LOCAL = grep /^--local$/, @ARGV;
@ARGV = grep !/^--local$/, @ARGV;
# On recherche la presence d'une option --silent dans les arguments
our $SILENT = grep /^--silent$/, @ARGV;
@ARGV = grep !/^--silent$/, @ARGV;
# Extraction du parametre split
our $SPLIT;
our %SPLITTER;
{
my $split_pos, my $count=0;
if ( grep {$count++;my $found=/^--split$/;$split_pos=$count if $found;$found} @ARGV ) {
	$count=0;
	$SPLIT = (grep {$count++;$count==$split_pos+1} @ARGV)[0]; # Get the parameter AFTER --split
	&usage() unless $SPLIT;
	$count=0;
	@ARGV = grep {$count++;$count<$split_pos || $count>$split_pos+1} @ARGV;
	@ARGV = ('-f', 'STDOUT', @ARGV);
	}
}

undef $\ if $CSV || $REPORT || $SPLIT;

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

our $currentList;

# Loads the configuration
our @SBIRES;
our %SBIRES = &readSbireFile($Config{'SBIRE_LIST'});

if (lc $files eq 'list') {
	# List all sbires
	$,=$\;print grep /\w/, @SBIRES;
	exit(0);
}

my $MULTIPLE = ($files=~/^\@/) || ($files=~/^all$/i) || ($files=~/,/);

$MULTIPLE=0 if $LOCAL && "@ARGV"!~/__(NAME|TARGET)__/; # Only one iteration if file=='all' but the command is local and no MACRO is used
# Allow local command even without server defined
$files='local' if $LOCAL && !$files;


if ($MULTIPLE && $files=~s/^\@//) {
	# Load list of server names from a file
	my $baseListDir='.';
	my @listFiles;
	my $multiList=0;
	if ($files=~/\*/ ) {
		$multiList=1;
		# Look for list files
		my $glob = "$baseListDir/$files.lst";
		@listFiles = grep { -f } < $glob >;
	} else {
		# open file list
		$baseListDir= $CONFIG_DIR unless -f "$CONFIG_DIR/$files.lst";
		die ("$baseListDir/$files.lst not found") unless -f "$baseListDir/$files.lst";
		@listFiles = ( "$baseListDir/$files.lst" );
	}
	foreach my $currentFileList (@listFiles) { 
		$currentList = $currentFileList;$currentList=~s!.*/(.*?)\.lst!\1!;
		print "================== $currentList ===============\n" if $multiList;
		open LST, $currentFileList;
		map {
			chomp;
			if (defined $SBIRES{$_}) {
				&process($_);
			} else {
				print "$_\tServer not found in server list\n";
			}
		} grep /\w/, map {s/[#; ].*//;$_} <LST>;
		close LST;
	}
}
else {
	# filter servers by name
	my $ifiles = $files;
	$files=~s/\*/.*/g;
	$files=".*" if (lc $files eq 'all');
	$files=~s/,/|/g;
	my @slist = grep /^$files$/i, grep /\w/, @SBIRES;
	print "$ifiles\tServer not found in server list" unless @slist;
	foreach (@slist) { 
		&process($_);
		last unless $MULTIPLE;
	};
	printReport() if $REPORT;
}

# Post-process :: --split

if ($SPLIT) {
	$\=$/;print;
	my $count=0;
	foreach my $key (sort keys %SPLITTER) {
		$count++;
		# Generate a split-file
		my $splitname="$SPLIT-$count";
		my @aliases = @{ $SPLITTER{$key} };
		# Generate the output
		{ 
		local $\;undef $\;
		open OUTPUT, ">$splitname.out";
		print OUTPUT $key;
		close OUTPUT;
		}
		# Generate the listfile
		open LIST, ">$splitname.lst";
		print LIST join $/,@aliases;
		close LIST;
		print "$splitname.out written (" . (join ',', sort @aliases) . ")";
	}
}
exit(0);

# ------------------------------------------------

sub usage() {
	print "Sbire_Sergeant :";
	print "   (TODO : This usage is for direct use of 'sergeant' which is not generally the case. aliases 'connect', 's', 'c', 'r' are now prefered.)";
	print 'Usage : sb_sergeant.pl list';
	print '        sb_sergeant.pl <SERVER_NAME> [--csv] [--local] [ -c <COMMAND> args... ]';
	print '        sb_sergeant.pl @<LIST_FILE>  [--csv] [--local] [ -c <COMMAND> args... ]';
	print '        sb_sergeant.pl    all        [--csv] [--local] [ -c <COMMAND> args... ]';
	print "Commands : ";
	print "   -c upload   -f <local_file> -n <filename> ";
	print "   -c download -n <filename> [-f <local_file>] [ --split <file> ]";
	print "   -c run [-d <dir>] [ --split <file> ] -- <cmdline>";
	print "   -c config [ --split <file> ] -- <name> <value>";
	print "   -c info [ -n <plugin_path> ] [ --split <file> ] [--report]";
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
	my @args = map "'$_'", @ARGV;

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
			print "LOCAL (alias:$alias)> $cmd\n";
		} elsif ($command eq 'info') {
		    my $file = join '%',@args; 
		  	unless ($file=~s/(^|.*\%)-n\%([^\%]+)(\%.*|$)/$2/) {
				print "ERROR : -n <file> argument is mandatory";return;
			}
			# TODO : this could be better of course.
			my $sbire_path = $0; $sbire_path=~s/sb_sergeant/server_side\/sbire/;
			$cmd="/usr/bin/perl $sbire_path --direct info $file";
		} else {
			print "ERROR : $command is not available with --local option.";return;
		}
			
	} else {	
		# Local protocol
		my $header=""; 
		unless ($CSV or $REPORT or $SPLIT or ( ($command eq 'download') && !$MULTIPLE )) {
			$header="| $alias ($name) |"; 
			my $line="-" x length $header; 
			$header="$line\n$header\n$line";
		} 

		print $header unless $SILENT;

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
	$cmd=~s/__LIST__/$currentList/g;
	
	#print $cmd;
	my $output = `$cmd`;
	if ($SPLIT) {
		my @splitter = defined $SPLITTER{$output} ? @{$SPLITTER{$output}} : ();
		push @splitter, $alias;
		$SPLITTER{$output} = \@splitter;
	}
	if ($?) {
		print "ERROR : $!\n$output";
		return;
		}
	if (($CSV || $REPORT) && ! $LOCAL) {
		# With CSV output, each line must be prefixed by the server's name
		chomp $output;
		$output="\n" if $output eq '';
		$output=~s/^/$alias\t/gm;
	}
	print $output unless $SILENT || $SPLIT || $REPORT;
	push @REPORT,split $/,$output if $REPORT;
	print '.' if $REPORT or $SPLIT;     # Show a pending '......'
}

sub printReport() {
	print $/;
	my @lines=grep !/\t#HEADER#\s+/, @REPORT;
	my %HASH; # Hash contenant des refs de hash : {file}->\{version}->\{signature}->\[server,...]
	my %SERVERS; # Known servers
	foreach (@lines) {
		my($server,$file,$size,$version,$signature)=split /\t/;
		$HASH{$file}{$version}{$signature}=[] unless $HASH{$file}{$version}{$signature};
		push @{$HASH{$file}{$version}{$signature}}, $server;
		$SERVERS{$server}=1;
	}
	my @SERVERS = keys %SERVERS;
	# On affiche les plugins homogènes
	local $\=$/;
	foreach (sort keys %HASH) {
		next if /does not exist/;
		next unless /\w/;
		my $file=$_;
		print "\n$file :";
		my @versions = keys %{$HASH{$file}};
		my $nversion = 0;
		foreach my $version (@versions) {
			foreach (keys %{$HASH{$file}{$version}}) {
				$nversion++;
				}
			}
		my $unique = ($nversion == 1); # only one version
		my @absent = grep {
			my $server=$_;
			my $present=0;
			foreach my $version (@versions) {
				foreach my $sig (keys %{$HASH{$file}{$version}}) {
					my @servers = @{$HASH{$file}{$version}{$sig}};
					map {$present = 1 if $server eq $_} @servers;
					}
				}
			! $present
			} @SERVERS; # servers where this file is absent
		print "\t\t(absent)\t".(join ',', @absent) if @absent;
		foreach (sort @versions) {
			my $version=$_;
			my @signatures = keys %{$HASH{$file}{$version}};
			if (@signatures==@SERVERS and @signatures>3) {
				print "\t\t(all different)";
			} elsif (@signatures==@SERVERS-@absent and @signatures>3) {
				my $servers=join ',', map{ @{$HASH{$file}{$version}{$_}} }@signatures;
				print "\t\t(all different)\t$servers";
			} elsif (@signatures==1 && $version) {
				my $sig = $signatures[0];
				my @servers = @{$HASH{$file}{$version}{$sig}};
				my $servers = join ',', @servers;
				$servers = '(all)' if (@servers == @SERVERS or $unique) and @servers > @absent and @servers > 3;
				print "\t\t$version\t$servers";
			} else {
				# A same version has several signatures or the version is empty/null
				foreach (sort @signatures) {
					my $sig=$_;
					my @servers = @{$HASH{$file}{$version}{$sig}};
					my $servers = join ',', @servers;
					$servers = '(all)' if (@servers == @SERVERS or $unique) and @servers > @absent and @servers > 3;
					$sig=~s/(.....).*/$1.../;
					print "\t\t$version($sig)\t$servers";
				}
			}
		}
	}
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
	close CFG;
	%CONF;
}

