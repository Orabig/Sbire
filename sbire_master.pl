#!/usr/bin/perl

####################
#
# sbire_master.pl
#
# Version 0.9.2
#
# Historique : 0.9.1 :  First public revision
#              0.9.2 :  Improved configuration file
#						Changed 'update' command to 'upload'
# 
# NRPE plugins update/manage master script
#
# Usage : sbire_master.pl -H <IP> -c upload -n <name> -f <file> [ -v 1 ]
#         sbire_master.pl -H <IP> -c chmod -n <name> -m <mod>
#         sbire_master.pl -H <IP> -c info -n <name>
#         sbire_master.pl -H <IP> -c restart
# 
####################

use strict;
$\=$/;

my $CONFIGFILE;
our ($CHUNK_SIZE, $privkey, $NRPE, $USE_ZLIB_COMPRESSION, $USE_RSA, $USE_SSH);
{
	# Default config file
	$CONFIGFILE = $^O=~/Win/ ? './sbire_master.conf' : '/etc/sbire_master.conf';
	# Read config file as first argument
	$_ = $ARGV[0];
	if (defined $_ && !/^-/) {
		# Lets assume that this first argument is the path to the config file
		$CONFIGFILE = $_;
		}
	unless (-e $CONFIGFILE) {
		print "Configuration file $CONFIGFILE does not exist. Creating...";
		open CF, ">$CONFIGFILE";
		print CF <<_EOF_;
# Sample configuration file
\$CHUNK_SIZE = 832;
\$privkey = '/usr/local/nagios/bin/sbire_key.private';
\$NRPE = '/usr/local/nagios/libexec/check_nrpe';
\$USE_SSH = 1;
\$USE_RSA = 1;
\$USE_ZLIB_COMPRESSION = 1;
1;
_EOF_
		close CF;
		}
	die ("Could not initialize configuration file") unless (-e $CONFIGFILE);
	require $CONFIGFILE;
}

die ("NRPE could not be found at $NRPE") unless (-x $NRPE);
	
use MIME::Base64; 
use Digest::MD5 qw(md5_hex);
 
my ($command,$dest,$file,$name,$mod);
my ($help,$verbose);
&getOptions(
	"c" => \$command,
	"H" => \$dest,
	"v" => \$verbose,
	"n" => \$name,
	"f" => \$file,
	"m" => \$mod,
	"h" => \$help
);
	
&error("Name must not contain special characters (only alpha and .)") if $name=~/[^\w\.]/;
&error("Destination (-H) is mandatory") unless defined $dest;
&usage() if defined $help;

unless (defined $command) {
	print &call_sbire(' ');
	exit(0);
}

if ($command eq 'upload') {
	&update($file,$name,$verbose);
} elsif ($command eq 'restart') {
	&restart();
} elsif ($command eq 'info') {
	&info($name);
} elsif ($command eq 'chmod') {
	&chmod($name,$mod);
} else {
	&error("Command '$command' unknown");
}

sub usage {
	print "Usage : sbire_master.pl -H <IP> -c upload -n <name> -f <file> [ -v 1 ]";
	print "        sbire_master.pl -H <IP> -c chmod -n <name> -m <mod>";
	print "        sbire_master.pl -H <IP> -c info -n <name>";
	print "        sbire_master.pl -H <IP> -c restart";
}
sub error {
	my ($msg)=@_;
	print $msg;
	&usage();
	exit(1);
}
# -----------------------------------------------

sub chmod {
	my ($name,$mod)=@_;
	print &call_sbire("chmod $name $mod");
}

sub info {
	my ($name)=@_;
	print &call_sbire("info $name");
}

sub restart {	
	$_ = &call_sbire("restart",1);
	if (/Received 0 bytes from daemon/) {
		# Tout va bien. Le service s'est coupe et n'a pas eu le temps de repondre.
		print "Service NRPE restart [ OK ]";
		exit(0);
		}
	if (/sudo: no tty present/) {
		print "You MUST add nagios user in sudoers on distant server. Execute on $dest :";
		print 'root@'.$dest.'# echo "nagios ALL = NOPASSWD: `which service`" >>/etc/sudoers';
		exit(1);
		}
	print ;
	exit(1);
}


sub update {
	my ($file,$name,$verbose)=@_;

	# Lecture du fichier
	print "Reading file" if ($verbose);
	open INF, $file or die "\nCan't open $file: $!\n";
	binmode INF;
	my $content = do { local $/; <INF> };
	close INF;
	
	# Verification de la version du fichier
	$_ = &call_sbire("info $name");
	if (/Signature\W+([\w]+)/) {
		my $md5=$1;
		# Verification de notre propre signature
		my $mymd=md5_hex($content);
		if ($md5 eq $mymd) {
			print "Files are identical. Skip...";
			exit(0);
			}
	}
	
	# Demande d'un nouvel ID de session
	my $ID = &call_sbire("send newfile");

	# Compression
	my $zcontent;
	if ($USE_ZLIB_COMPRESSION) {
		eval("use Compress::Zlib");
		{
			local $\;
			print "Compressing..." if ($verbose);
		}
		my $zcontent=compress($content);
		print " Ratio : ".int(100-100*length($zcontent)/length($content))."%" if ($verbose);
	} else { $zcontent=$content; }

	# Conversion en base 64
	print "Converting to base64" if ($verbose);
	my $offset=0;
	my $content64=encode_base64($zcontent,'');
	
	# Decoupage en chunks et envoi
	print "Sending..." if ($verbose);
	while ($content64=~/.{1,$CHUNK_SIZE}/g) {
		my $chunk64=$&;
		my $args="send $ID $chunk64 $offset";
		$_ = &call_sbire($args);
		/OK (\d+)/ or die ("Unknown sbire response : $_");
		$offset = $1;
		{ local $\;print "." unless ($verbose>1); }
	}
	# Fin de l'envoi
	print "\nSent." if ($verbose);
	print "Size=".length($content64)." bytes" if ($verbose);
	print "Session ID=$ID" if ($verbose);
	
	# Calcul de la signature
	my $signature;
	if ($USE_RSA) {
		eval("use Crypt::RSA");
		my $rsa = new Crypt::RSA;
		my $myPrivateKey = new Crypt::RSA::Key::Private (
							Filename => $privkey
						   ) || die $rsa->errstr();
						   
		$signature =  $rsa->sign ( 
				Message    => $content, 
				Key        => $myPrivateKey
			) || die $rsa->errstr();
		$signature=encode_base64($signature,'');
	} else {
		$signature="unsigned";
	}
					   
	# Mise a jour du fichier distant
	my $args="update $name $ID $signature";
	$_=&call_sbire($args);
	print;
}		

sub call_sbire {
	my ($args,$ignore_err)=@_;
	my $nrpe_arg = $USE_SSH ? "" : "-n";
	my $cmd;
	if ($dest=~/^(.*):(\d+)$/) {
		$cmd="$NRPE -H $1 -p $2 $nrpe_arg -c sbire -a \" $args\"";
	} else {
		$cmd="$NRPE -H $dest $nrpe_arg -c sbire -a \" $args\"";
	}
	print "sbire > $cmd" if ($verbose>1);
	my $result = qx!$cmd!;
	if ($? && !$ignore_err) {
		print "Error on > $cmd" if ($verbose);
		chomp $result;
		# Analyse des erreurs connues
	#	if ($result=~/sh:.*sbire.pl: Permission denied/) {
	#		print "$result\nCheck sbire.pl execution status on distant server.";
	#		print "Try:    chmod a+x /usr/local/";
	#		exit($?);
	#		}
		print $result;
		exit($?);
	}
	chomp $result;
	print $result if ($verbose>2);
	return $result;
}

sub getOptions() {
        my %varRef=@_;
        my $ARGS = join ' ',@ARGV;
        my $ARG1='';
        my $ARG2='';
        ($ARG1,$ARG2) = split / *--/, $ARGS;
        if (defined $ARG2) {
                if (defined $varRef{'-'}) {
                        ${$varRef{'-'}} = $ARG2;
                } else {
                        print "Parametre -- non defini";exit 3;
                }
        }
        return if (!defined $ARG1);
        my @array = split / *-([a-zA-Z])(?: |$)/,$ARG1;
        my %params;
        if ((+ @array)%2 == 0) {
                (undef,%params) = (@array,'');
                } else {
                (undef,%params) = @array;
                }
        foreach (keys %params) {
                my $cle = $_;
                my $val = $params{$cle};
                if (defined $varRef{$cle}) {
                        ${$varRef{$cle}} = $val;
                        }
                        else {
                        print "Parametre -$cle inconnu";exit 3;
                        }
                }
        }

