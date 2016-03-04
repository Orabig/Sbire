#!/usr/bin/perl

####################
#
# sbire_master.pl
# 
# NRPE plugins update/manage master script
#
# Usage : sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c upload -n <name> -f <file> [ -v 1 ]
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c download -n <name> -f <file>
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c run [-d <dir>] -- <cmdline>
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c config [-n <config_file_name>] [-- <OPTION> <value>]
#         sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c info -n <name>
#         sbire_master.pl -H <IP> -P NRPE           -c nrpe [ -n <name> ] [ -- <ATTRIBUTES> ]
# 
####################

use strict;
$\=$/;

my $CONFIGFILE;
our ($CHUNK_SIZE, $privkey, $NRPE, $USE_ZLIB_COMPRESSION, $USE_RSA);
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
\$NRPE = '/usr/lib/nagios/iplugins/check_nrpe';
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
 
my ($protocol,$command,$dest,$file,$name,$cmdline,$dir,$NRPEnossl,$ssh_path);
my ($help,$verbose);
&getOptions(
	"P" => \$protocol,
	"p" => \$ssh_path,
	"c" => \$command,
	"H" => \$dest,
	"v" => \$verbose,
	"n" => \$name,
	"S" => \$NRPEnossl, # -S 1 means that NRPE command must use the -n option (NO SSL)
	"f" => \$file,
	"d" => \$dir,
	"-" => \$cmdline,
	"h" => \$help
);
	
&error("Destination (-H) is mandatory") unless defined $dest;
&usage() if defined $help;
	
unless ($file) {
	$file=$name;
	$file=~s/.*(\\|\/)//;
}

# transforme les caracteres interdits pour NRPE en meta-caractere
$name   =~s/[^\w ]/'%'.sprintf("%x",ord $&)/ge;
$cmdline=~s/[^\w ]/'%'.sprintf("%x",ord $&)/ge;
$dir    =~s/[^\w ]/'%'.sprintf("%x",ord $&)/ge;

unless (defined $command) {
	print &call_sbire(' ');
	exit(0);
}

if ($command eq 'upload') {
	&upload($file,$name,$verbose);
} elsif ($command eq 'info') {
	&info($name);
} elsif ($command eq 'nrpe') {
	&nrpe($name,$cmdline);
} elsif ($command eq 'download') {
	&download($file,$name,$verbose);
} elsif ($command eq 'config') {
	&config($name,$cmdline);
} elsif ($command eq 'run') {
	&run($cmdline,$dir);
} else {
	&error("Command '$command' unknown");
}

sub usage {
	print "Usage : sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c upload -n <remote_file> [-f <local_file>]";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c download -n <remote_file> [-f <local_file>]";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c run [-d <dir>] -- <cmdline>";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c config [-n <config_file_name>] [-- <OPTION> <value>]";
	print "        sbire_master.pl -H <IP> -P LOCAL|NRPE|SSH -c info -n <name>";
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
	$dir="-$dir-" if $dir;
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
	my ($name,$cmdline)=@_;
	$name='-' unless $name;
	print &call_sbire("config $name $cmdline");
}

sub download {
	my ($file,$name,$verbose)=@_;
	if (-f $file) {
		# The file exists, so we should check if a download is necessary
		my $localContent=readFileContent($file);
		exitIfRemoteContentIsIdentical($name, $localContent);
	}
	my $content=&call_sbire("download $name");
	undef $\;
	if ($file eq 'STDOUT') {
		print $content;
	} else {
		print "Writing file$/" if ($verbose);
		open INF, ">$file" or die "\nCan't open $file for writing: $!\n";
		binmode INF;
		print INF $content;
		close INF;
		my $len=length($content);
		print "Downloaded $len bytes to $file$/";
	}
	exit(0);
}

sub upload {
	my ($file,$name,$verbose)=@_;
	# Lecture du fichier
	print "Reading file" if ($verbose);
	my $content=readFileContent($file);
	
	my $mymd=exitIfRemoteContentIsIdentical($name, $content);
	
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

sub readFileContent() {
	my ($file)=@_;
	open INF, $file or die "\nCan't open $file: $!\n";
	binmode INF;
	my $content = do { local $/; <INF> };
	close INF;
	return $content;
}

# This sub control if the given content is identical to the remote content (with MD5)
# It then returns the MD5 of the local content, or exit the program if contents are identical
sub exitIfRemoteContentIsIdentical() {
	my ($name, $content)=@_;
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
	return $mymd;
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
	print "(Complete decoded output is ".length($result)." bytes)" if ($verbose);
	
	if ($? && !$ignore_err) {
		print "Error on > $cmd" if ($verbose);
		# Analyse des erreurs connues (et affichage de solutions appropriees)
	#	if ($result=~/sh:.*sbire.pl: Permission denied/) {
	#		print "$result\nCheck sbire.pl execution status on distant server.";
	#		print "Try:    chmod a+x /usr/local/";
	#		exit($?);
	#		}
		print $result;
		exit($?);
	}
	print $result if ($verbose>2);
	return $result;
}

sub get_output {
	my ($cmd) = @_;
	print "> $cmd" if ($verbose);
	my $output=qx!$cmd!;
	print "(output ".length($output)." bytes)" if ($verbose);
	return $output=~/^b\*64_(.*)_b64$/sm ? decode_base64($1) : $output;
}

sub buildNrpeCmd() {
	my ($name,$params)=@_;
	my $cmd;
	if (uc $protocol eq 'NRPE') {
		my $nrpe_arg = $NRPEnossl ? "-n" : "";
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
		my $nrpe_arg = $NRPEnossl ? "-n" : "";
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
        $_ = join ' ',@ARGV;
        if (/^(.*?) --(.*)/) {
                if (!defined $varRef{'-'}) {
                        print "Parametre -- non defini";exit 3;
                }
				$_=$1;
				${$varRef{'-'}} = $2;
        }
        return if (!defined $_);
        my @array = split / *-([a-zA-Z])(?: |$)/,$_;
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


