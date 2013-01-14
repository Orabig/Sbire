#!/usr/bin/perl

my $Version= 'Version 0.9.3';

####################
#
# sbire.pl
#
# 
# NRPE plugins update/manage script
#
# Usage : (must be run from NRPE)
#
#    sbire.pl send newfile 
#		Creates a new session ID for file sending
#
#    sbire.pl send <ID> <chunk_b64> <offset>
#		Send a new chunk (part of a new file) into the quarantine directory
#
#    sbire.pl update <name> <sessionID> <signature>
#		Creates or updates a plugin/file with the previously sent file. If sessionID has ".z" suffix, then the file must be uncompressed.
#
#    sbire.pl chmod <name> <chmod> 
#		Creates or updates a plugin/file with the previously sent file
#
#    sbire.pl info <name>
#		Gets informations about a plugin.file (size, checksum and version if any)
#
#    sbire.pl restart
#		Relance le service nrpe. Sur les systèmes *Nix, le compte nrpe (nagios) doit être déclaré lors de 
#		l'installationdans les sudoers de la façon suivante :
#			echo "nagios ALL = NOPASSWD: `which service`" >>/etc/sudoers
#		La relance n'a pas encore été testée sur Windows
####################

 use MIME::Base64;
 use File::Copy;
 use Digest::MD5 qw(md5_hex);
 
 $\=$/;
 use strict;
 
 # Definition du fichier de configuration
 our ($pubkey,$SESSIONDIR,$ARCHIVEDIR,$PLUGINSDIR,$USE_RSA,$NRPE_SERVICE_NAME);
 my $CONF = shift(@ARGV);
 
 exit(1) unless defined $CONF; # TODO : Usage
 
 unless (-e $CONF) {
	print "Configuration file missing. Init with default values";
	open CF, ">$CONF" || &error("Cannot write $CONF");
	print CF <<__EOF__;
 # sbire.pl configuration file.
 \$pubkey = '/usr/local/nagios/bin/sbire_key.pub';
 
 \$SESSIONDIR = '/tmp/sbire';
 \$ARCHIVEDIR = '/usr/local/nagios/libexec/archive';
 \$PLUGINSDIR = '/usr/local/nagios/libexec';
 
 \$USE_RSA = 1;
 \$NRPE_SERVICE_NAME = nrpe;
 
 1;
__EOF__
	close CF;
	&error("Cannot write $CONF") unless (-e $CONF);
	}

 require $CONF;
 mkdir($SESSIONDIR) unless (-d $SESSIONDIR);
 mkdir($ARCHIVEDIR) unless (-d $ARCHIVEDIR);
 mkdir($PLUGINSDIR) unless (-d $PLUGINSDIR);

# Configuration check
&error("Configuration error : PLUGINSDIR ($SESSIONDIR) does not exist or is not writable") unless (-w $SESSIONDIR);
&error("Configuration error : ARCHIVEDIR ($ARCHIVEDIR) does not exist or is not writable") unless (-w $ARCHIVEDIR);
&error("Configuration error : PLUGINSDIR ($PLUGINSDIR) does not exist or is not writable") unless (-w $PLUGINSDIR);

 my $COMMAND = shift(@ARGV);

 unless (defined $COMMAND) {
	print "Sbire.pl $Version";
	exit(0);
	}
 
 if ($COMMAND eq 'send') 
	{ &send }
 elsif ($COMMAND eq 'update') 
	{ &update }
 elsif ($COMMAND eq 'restart') 
	{ &restart }
 elsif ($COMMAND eq 'chmod') 
	{ &chmod }
 elsif ($COMMAND eq 'info') 
	{ &info }
 else 
	{ &error("Command '$COMMAND' unknown.") }
 
 exit(0);
 
 sub send {
	my $ID = shift(@ARGV);
	if ($ID eq 'newfile') {
		# Creation d'un nouvel ID de session
		do {
			$ID = int(rand(100000));
		} until (! -f "$SESSIONDIR/$ID.chunks");
		print $ID;
		exit(0);
	}
	# Reception d'un chunk
	my ($chunk64,$offset) = @ARGV;

	# Check if offset is correct
	my $file = "$SESSIONDIR/$ID.chunks";
	my $filesize = -s $file;
	&error("Bad offset") unless ($offset == $filesize);
	
	# Append chunk to session file
	{
		local $\;
		my $chunk = decode_base64($chunk64);
		open OUTPUT, ">> $file" || die "Cannot append to $file: $!";
		binmode OUTPUT;
		print OUTPUT $chunk;
		close OUTPUT;
	}
	
	&error("Cannot write to $file") unless -e $file;
	# Compute new size
	$filesize = -s $file;
	print "OK $filesize";
	exit(0);
 }
 
 sub update {
	my ($name,$ID,$signature) = @ARGV;
	
	my $zlib = $ID=~s/\.z$//;
	my $chunks = "$SESSIONDIR/$ID.chunks";
	my $plugin = "$PLUGINSDIR/$name";
	
	# Verification : le fichier doit exister
	&error("Session $ID does not exist.") unless (-f $chunks);
	
	# Trouver un numero libre pour l'archive
	my $maxidx=1;
	map {/\.(\d+)$/; $maxidx=$1+1 if $1>=$maxidx} <$ARCHIVEDIR/$name.*>;
	my $archive="$ARCHIVEDIR/$name.$maxidx";
	
	# Lecture du fichier chunks
	open INF, $chunks or die "Cannot open $chunks: $!";
	binmode INF;
	my $content = do { local $/; <INF> };
	close INF;
	
	# Decompression
	if ($zlib) {
		use Compress::Zlib;
		$content = uncompress($content);
		}
	
	# Verification : la signature doit être correcte
	
	$signature=decode_base64($signature);
	
	if ($USE_RSA) {
		eval("use Crypt::RSA");
		my $rsa = new Crypt::RSA; 
		my $PublicKey = new Crypt::RSA::Key::Public (
							Filename => $pubkey
						   ) || die $rsa->errstr();
		my $verify = $rsa->verify (
				Message    => $content, 
				Signature  => $signature, 
				Key        => $PublicKey
			) || &error("Security check failed");		
		&error("Security check failed") unless $verify;
	}
		
	# Archiver l'ancien fichier (s'il existe)
	-f $plugin && ( move($plugin,$archive) || &error("Cannot backup last revision. Is $archive writtable ?") );
	
	# Ecrire le nouveau fichier
	open OUTPUT, ">$plugin" || die ("Cannot write to $plugin");
	binmode OUTPUT;
	{ local $\; print OUTPUT $content; }
	close OUTPUT;
	
	# Si le fichier est sbire.pl lui-même, alors ajoute le flag execute (sinon on sera coince...)
	if ($name eq 'sbire.pl') {
		`chmod a+x $plugin`;
		}
	
	# Supprimer le fichier de session
	unlink($chunks);
	print "OK";
	exit(0);
 }
 
 sub restart {
	$_=`sudo service $NRPE_SERVICE_NAME restart`;
	print "Service $NRPE_SERVICE_NAME restart : $_";
}
 
 sub chmod {
 	my ($name,$mod) = @ARGV;
        $_ = "$PLUGINSDIR/$name";
	&error("$name does not exist") unless -f;
	`chmod $mod $_`;
	my $result="";
	$result .= (-r) ? 'r':'-';
	$result .= (-w) ? 'w':'-';
	$result .= (-x) ? 'x':'-';
	print "$name : $result";
}
 
sub info {
 	my ($name) = @ARGV;
        my $plugin = $name=~/\d$/ ? "$ARCHIVEDIR/$name" : "$PLUGINSDIR/$name";
	unless (-f $plugin) {
		print ("$name does not exist");
		exit(0);
		}
	my $size = -s $plugin;
	# Lecture du numero de version
	open INF,$plugin || &error("Cannot open $name");
	binmode INF;
        $_ = do { local $/; <INF> };
        close INF;
	my $Version="-";
	$Version=$1 if /Version\W+([\d\.\-]+\w*)/i;
	my $MD5=md5_hex($_);
	print "$name : (${size} bytes)     Version : $Version      Signature : $MD5";
 }
 
 sub error() {
	my ($msg)=@_;
	print $msg;
	exit(1);
 }
 
 
