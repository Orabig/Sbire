#!/usr/bin/perl

####################
#
# sbire_master.pl
#
# Version 0.9.10
#
# Historique : 0.9.1 :  First public revision
#              0.9.2 :  Improved configuration file
#						Changed 'update' command to 'upload'
#              0.9.3 :  Different protocols may be used (LOCAL and NRPE so far)
#              0.9.3 :  Added 'download' command
#              0.9.4 :  Added illegal NRPE character conversion
#						Added 'options' command
#              0.9.5 :  Fixed problems by changing -e to -- argument
#              0.9.6 :  The script can now be invoked from another directory
#              0.9.7 :  Added SSH support
#              0.9.8 :  Added NRPE command
#              0.9.9 :  Added NRPE attributes
#              0.9.10:  Added the optional -d <dir> argument to run command
# 
# NRPE plugins update/manage master script
#
# Usage : sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c upload -n <name> -f <file> [ -v 1 ]
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c download -n <name> -f <file>
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c run [-d <dir>] -- <cmdline>
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c config -- <OPTION> <value>
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c options
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c info -n <name>
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c restart
#         sbire_master.pl -H <IP> -P NRPE           -c nrpe [ -n <name> ] [ -- <ATTRIBUTES> ]
# 
####################

use strict;
$\=$/;

my $CONFIGFILE;
our ($CHUNK_SIZE, $privkey, $NRPE, $USE_ZLIB_COMPRESSION, $USE_RSA, $USE_SSH);
{
	# Default config file
	my $ROOT_DIR = $0;$ROOT_DIR=~s!/[^/]*$!!;
	$CONFIGFILE = $^O=~/Win/ ? './sbire_master.conf' : "$ROOT_DIR/etc/sbire_master.conf";
	$CONFIGFILE = '/etc/sbire_master.conf' unless -f $CONFIGFILE;
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

# die ("NRPE could not be found at $NRPE") unless (-x $NRPE);
	
use MIME::Base64; 
use Digest::MD5 qw(md5_hex);
 
my ($protocol,$command,$dest,$file,$name,$cmdline,$dir,$NRPEnossh,$ssh_path);
my ($help,$verbose);
&getOptions(
	"P" => \$protocol,
	"p" => \$ssh_path,
	"c" => \$command,
	"H" => \$dest,
	"v" => \$verbose,
	"n" => \$name,
	"S" => \$NRPEnossh,
	"f" => \$file,
	"d" => \$dir,
	"-" => \$cmdline,
	"h" => \$help
);
	
&error("Destination (-H) is mandatory") unless defined $dest;
&usage() if defined $help;

# transforme les caracteres interdits pour NRPE en meta-caractere
$name   =~s/[\%\\\&\|\'\"\{\}\;]/'%'.sprintf("%x",ord $&)/ge;
$cmdline=~s/[\%\\\&\|\'\"\{\}\;]/'%'.sprintf("%x",ord $&)/ge;

unless (defined $command) {
	print &call_sbire(' ');
	exit(0);
}

if ($command eq 'upload') {
	&upload($file,$name,$verbose);
} elsif ($command eq 'restart') {
	&restart();
} elsif ($command eq 'info') {
	&info($name);
} elsif ($command eq 'nrpe') {
	&nrpe($name,$cmdline);
} elsif ($command eq 'download') {
	&download($file,$name,$verbose);
} elsif ($command eq 'config') {
	&config($cmdline);
} elsif ($command eq 'options') {
	&options();
} elsif ($command eq 'run') {
	&run($cmdline,$dir);
} else {
	&error("Command '$command' unknown");
}

sub usage {
	print "Usage : sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c upload -n <name> -f <file>";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c download -n <name> [-f <file>]";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c run [-d <dir>] -- <cmdline>";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c config -- <OPTION> <value>";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c options";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c info -n <name>";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c restart";
	print "        sbire_master.pl -H <IP> -P NRPE           -c nrpe [ -n <name> ] [ -- <parameters> ]";
}
sub error {
	my ($msg)=@_;
	print $msg;
	&usage();
	exit(1);
}
# -----------------------------------------------

sub run {
	my ($cmdline,$dir)=@_;
	$dir="[$dir]" if $dir;
	print &call_sbire("run $name $dir $cmdline");
}

sub info {
	my ($name)=@_;
	print &call_sbire("info $name");
}

sub nrpe {
    my ($name,$params)=@_;
	print get_output(&buildNrpeCmd($name, $params));
}

sub config {
	my ($name)=@_;
	print &call_sbire("config $name");
}

sub options {
	print &call_sbire("options");
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


sub download {
	my ($file,$name,$verbose)=@_;
	my $content=&call_sbire("download $name");
	print "Writing file" if ($verbose);
	unless ($file) {
		undef $\;
		print $content;
	} else {
		open INF, ">$file" or die "\nCan't open $file for writing: $!\n";
		binmode INF;
		print INF $content;
		close INF;
		my $len=length($content);
		print "Downloaded $len bytes to $file.";
	}
	exit(0);
	}

sub upload {
	my ($file,$name,$verbose)=@_;
	
	# Lecture du fichier
	print "Reading file" if ($verbose);
	open INF, $file or die "\nCan't open $file: $!\n";
	binmode INF;
	my $content = do { local $/; <INF> };
	close INF;
	
	# Verification de la version du fichier
	$_ = &call_sbire("info $name",1);
	my $mymd=md5_hex($content);
	if (/Signature\W+([\w]+)/) {
		my $md5=$1;
		# Verification de notre propre signature
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
		$zcontent=compress($content);
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
		my ($k,$n)=readKeyFile($privkey);
		$signature = rsaCrypt($mymd,$k,$n);
		$signature=encode_base64($signature,'');	
	} else {
		$signature="unsigned";
	}
					   
	# Mise a jour du fichier distant
	my $args="update $name $ID $signature";
	$_=&call_sbire($args);
	print;
}		

sub readKeyFile() {
   my($file)=@_;
   open K,$file or die "\nCan't open private key file $file: $!\n";
   local $/;
   $_=<K>;
   close K;
   s/\W//g;
   my (undef,$k,$n)=split/0x/;
   return ($k,$n);
}

sub rsaCrypt() {
	my ($content,$k,$n)=@_;
	return "-" unless defined $n;
	$\=$/;
	local $/;
	$/=unpack('H*',$content);
	my $temp=&createTempFile();
	open DC,">$temp";
	print DC "16dio\U${k}SK$/SM$n\EsN0p[lN*1lK[d2%Sa2/d0<X+d*lMLa^*lN%0]dsXx++lMlN/dsM0<j]dsjxp";
	close DC;
	$_=`dc $temp`;
	unlink($temp);
	s/\W//g;
	$_=pack('H*',/((..)*)$/);
 }
 
 sub createTempFile() {
	use POSIX;
	return tmpnam();
	}

sub call_sbire {
	my ($args,$ignore_err)=@_;

	$args=~s/"/\\\\"/g;
	my $cmd=&buildCmd($args); 
	
	print "sbire > $cmd" if ($verbose>1);
	my $result = get_output($cmd);
	
	# Loop : while the result ends with ___Cont:xxx___, then another request must be done
	while ($result=~/___Cont:(\d+)___$/) {
		my $remove=$&;
		$cmd=&buildCmd("continue $1");
		print "sbire > $cmd" if ($verbose>1);
		$result=substr($result,0,length($result)-length($remove)-1);
		$result .= get_output($cmd);
	}
	
	if ($? && !$ignore_err) {
		print "Error on > $cmd" if ($verbose);
		chomp $result;
		# Analyse des erreurs connues (et affichage de solutions appropriees)
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

sub get_output {
	my ($cmd) = @_;
	my $output=qx!$cmd!;
	return $output=~/^b\*64_(.*)_b64$/sm ? decode_base64($1) : $output;
}

sub buildNrpeCmd() {
	my ($name,$params)=@_;
	my $cmd;
	if (uc $protocol eq 'NRPE') {
		my $nrpe_arg = $NRPEnossh ? "" : "-n";
		my $nrpe_cmd;
		if ($dest=~/^(.*):(\d+)$/) {
			$nrpe_cmd="$NRPE -H $1 -p $2 $nrpe_arg";
		} else {
			$nrpe_cmd="$NRPE -H $dest $nrpe_arg";
		}
		$cmd=$nrpe_cmd;
		$cmd .= " -c $name" if $name=~/\w/;
		$cmd .= qq! -a "$params"! if $params;
	} else {
		&error("NRPE command incompatible with protocol '$protocol'.");
	}
	return $cmd;
}

sub buildCmd() {
	my ($args)=@_;
	my $cmd;
	if (uc $protocol eq 'NRPE') {
		my $nrpe_arg = $NRPEnossh ? "" : "-n";
		my $nrpe_cmd;
		if ($dest=~/^(.*):(\d+)$/) {
			$nrpe_cmd="$NRPE -H $1 -p $2 $nrpe_arg";
		} else {
			$nrpe_cmd="$NRPE -H $dest $nrpe_arg";
		}
		$cmd="$nrpe_cmd -c sbire -a \" $args\"";
	} elsif (uc $protocol eq 'SSH') {
		$cmd=qq!ssh $dest  "$ssh_path $args"!;
	} elsif (uc $protocol eq 'LOCAL') {
		$cmd="./sbire.pl /etc/sbire.cfg $args";
	} else {
		&error("Unkown protocol '$protocol'.");
	}
	return $cmd;
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


