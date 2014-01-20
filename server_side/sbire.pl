#!/usr/bin/perl

my $Version= 'Version 0.9.16';

####################
#
# sbire.pl
#
# 
# Remote control script
#
# History : 0.9.16 : enable uploading of files under 2 levels of directory, or empty files
#
# Usage :
#
#    sbire.pl <CFG> 
#		Returns version of the current script, as well as the actual configuration of its protocol
#       (NO_RSA / RSA & publickey, input limit, output limit)
#
#    sbire.pl <CFG> send newfile 
#		Creates a new session ID for file sending
#
#    sbire.pl <CFG> send <ID> <chunk_b64> <offset>
#		Send a new chunk (part of a new file) into the quarantine directory
#
#    sbire.pl <CFG> update <name> <sessionID> <signature>
#		Creates or updaes a plugin/file with the previously sent file. If sessionID has ".z" suffix, then the file is zipped and must be unpacked.
#       If <name>=PUBLIC_KEY then the public key file is written
#
#    sbire.pl <CFG> chmod <name> <chmod> 
#		Creates or updates a plugin/file with the previously sent file
#
#    sbire.pl <CFG> info <name>
#		Gets informations about a plugin.file (size, checksum and version if any). If name is omitted, then '*' is assumed.
#
#    Note : When the output of a command is longer than $OUTPUT_LIMIT (def. 1024), then it's truncated and ends with ___Cont:<id>___. The following
#          of the output may then be retreived with the following command.
#
#    sbire.pl <CFG> continue <sessionID>
#		Gets the output store in the given sessionID. (see above note)
#
#    sbire.pl <CFG> config <line>
#		Write the given line in the configuration file. Will not work if the config is locked.
#
#    sbire.pl <CFG> service
#       Loops and waits for "orders" to execute. The process thus runs indefinitely. It looks for data sources
#       defined in a "channel" list for orders documents, that have the following structure : {"ID":"<int>", 
#       "type":"<transfert|exec|info>", "fle":"<base64_encrypted_content>", "name":"<filename>"}
#
####################

 use MIME::Base64;
 use File::Copy;
 use Digest::MD5 qw(md5_hex);
 use File::Basename;
 
 use strict;
 no strict 'refs';
 
 my @options=qw!PUBLIC_KEY SESSIONDIR ARCHIVEDIR BASEDIR USE_RSA USE_RSA_DC_BASED_IMPLEMENTATION DC_PATH OUTPUT_LIMIT ALLOW_UNSECURE_UPLOAD ALLOW_UNSECURE_COMMAND CONFIG_LOCKED NRPE_SERVICE_NAME BASE64_TRANSFERT!;
 
 # Definition du fichier de configuration
 our ($PUBLIC_KEY,$SESSIONDIR,$ARCHIVEDIR,$BASEDIR,$USE_RSA,$USE_RSA_DC_BASED_IMPLEMENTATION,$DC_PATH,$OUTPUT_LIMIT,$ALLOW_UNSECURE_UPLOAD,$ALLOW_UNSECURE_COMMAND,$CONFIG_LOCKED,$NRPE_SERVICE_NAME,$BASE64_TRANSFERT);
 # Default values (security)
 $CONFIG_LOCKED = 0;
 $BASE64_TRANSFERT = 1;
 $OUTPUT_LIMIT = 640;
 $ALLOW_UNSECURE_UPLOAD = 0;
 $NRPE_SERVICE_NAME = 'nrpe';
 $DC_PATH = 'dc';
 
 our ($SERVICE);
 my $CONF = shift(@ARGV);
 
 unless (defined $CONF) {
	print "sbire.pl $Version\n";
	print "Usage : sbire.pl <config_file> [commands...]\n";
	exit(1);
	}
 
 unless (-e $CONF) {
	print "Configuration file missing. Init with default values";
	open CF, ">$CONF" || &error("Cannot write $CONF");
	print CF <<__EOF__;
 # sbire.pl configuration file.
 OUTPUT_LIMIT = 1024
 
 SESSIONDIR = /tmp/sbire
 ARCHIVEDIR = /var/nagios/archive
 BASEDIR = /usr/local/nagios
 
####################################################
#
# if USE_RSA is set to 1, then RSA protocol is used
# between master and sbires. This means that files
# sent by 'send' command are signed with master's
# private key. Drect commands are signed too.
#
# Sbires must then know the public key ($PUBLIC_KEY)
#
# if USE_RSA_DC_BASED_IMPLEMENTATION then the
# dc command is used to implement the RSA
# algorithms. If not, then the standard library
# Crypt::RSA is used and must be present in the
# system.
# If the first case, Windows system may use the
# Cygwin implementation (http://gnuwin32.sourceforge.net/packages/bc.htm)
#
####################################################
# USE_RSA = 1
# USE_RSA_DC_BASED_IMPLEMENTATION = 0

# PUBLIC_KEY = /usr/local/nagios/bin/sbire_key.pub

__EOF__
	close CF;
	&error("Canot write $CONF") unless (-e $CONF);
	}

 &readConfig($CONF);
 mkpath($SESSIONDIR) unless (-d $SESSIONDIR);
 mkpath($ARCHIVEDIR) unless (-d $ARCHIVEDIR);
 mkpath($BASEDIR) unless (-d $BASEDIR);

# Configuration check
&error("Configuration error : SESSIONDIR ($SESSIONDIR) does not exist or is not writable") unless (-w $SESSIONDIR);
&error("Configuration error : ARCHIVEDIR ($ARCHIVEDIR) does not exist or is not writable") unless (-w $ARCHIVEDIR);

 my $COMMAND = shift(@ARGV);


 unless (defined $COMMAND) {
	my $infos = "sbire.pl $Version ";
	my @more = ();
	# TODO
	push @more, $USE_RSA ? "RSA:pub=$PUBLIC_KEY" : "RSA:no";
	print $infos." (" . join(", ",@more).")\n";
	exit(0);
	}
 
 if ($COMMAND eq 'service') 
	{ $SERVICE=1; &service; }
else 
	{ run_command($COMMAND,@ARGV); }
	
 exit(0);

sub run_command {
	my ($COMMAND,@ARGS)=@_;

	# transforme les meta-caracteres interdits pour nrpe
	@ARGS = map {s/\%([a-f\d]{2})/chr(hex($1))/gei;$_} @ARGS;

	if ($COMMAND eq 'send') 
	{ &output(&send(@ARGS)) }
 elsif ($COMMAND eq 'update') 
	{ &output(&update(@ARGS)) }
 elsif ($COMMAND eq 'info') 
	{ &output(&info(@ARGS)) }
 elsif ($COMMAND eq 'download') 
	{ &output(&download(@ARGS)) }
 elsif ($COMMAND eq 'run') 
	{ &output(&run(@ARGS)) }
 elsif ($COMMAND eq 'options') 
	{ &output(&read_config()) }
 elsif ($COMMAND eq 'restart') 
	{ &output(&restart(@ARGS)) }
 elsif ($COMMAND eq 'continue') 
	{ &output(&contn(@ARGS)) }
 elsif ($COMMAND eq 'config') 
	{ &output(&write_config($CONF,@ARGS)) }
 else 
	{ &error("Sbire: Command '$COMMAND' unknown.") }
}

sub send {
	my $ID = shift;
	if ($ID eq 'newfile') {
		# Create a new session ID
		$ID = &newChunkId();
		# Create an empty file
		my $file = "$SESSIONDIR/$ID.chunks";
		open EMPTY, ">$file" || &error("Cannot create new $file: $!");
		close EMPTY;
		return $ID;
	}
	# Reception d'un chunk
	my ($chunk64,$offset) = @_;

	# Check if offset is correct
	my $file = "$SESSIONDIR/$ID.chunks";
	my $filesize = -s $file;
	&error("Bad offset") unless ($offset == $filesize);
	
	# Append chunk to session file
	&write_to_file($file , decode_base64($chunk64));
	
	&error("Cannot write to $file") unless -e $file;
	# Compute new size
	$filesize = -s $file;
	return "OK $filesize";
 }
 
 sub write_to_file() {
	my ($file,$chunk)=@_;
	local $\;
	open OUTPUT, ">> $file" || &error("Cannot append to $file: $!");
	binmode OUTPUT;
	print OUTPUT $chunk;
	close OUTPUT;
 }
 
 sub update {
	my ($name,$ID,$signature) = @_;
	
	my $zlib = $ID=~s/\.z$//;
	my $chunks = "$SESSIONDIR/$ID.chunks";
	my $plugin = "$BASEDIR/$name";
	
	$plugin=$PUBLIC_KEY if ($name eq 'PUBLIC_KEY');
	
	# Verification : le fichier doit exister
	&error("Session $ID does not exist.") unless (-f $chunks);
	
	&error("Unsecure upload forbidden.") unless ($ALLOW_UNSECURE_UPLOAD || $USE_RSA);
	
	
    # Flatten any directory and avoid weird characters
	my $archivedir=dirname("$ARCHIVEDIR/$name");
	-d $archivedir || mkpath($archivedir) || &error("Cannot create $archivedir for archive.");
	my $maxidx=1;
	map {/\.(\d+)$/; $maxidx=$1+1 if $1>=$maxidx} <$ARCHIVEDIR/$name.*>;
	my $archive="$ARCHIVEDIR/$name.$maxidx";
	
	# Lecture du fichier chunks
	open INF, $chunks or &error("Cannot open $chunks: $!");
	binmode INF;
	my $content = do { local $/; <INF> };
	close INF;
	
	# Decompression
	if ($zlib) {
		eval("use Compress::Zlib");
		&error("Compress::Zlib not present") if ($@);
		$content = uncompress($content);
		}
	
	# Verification : la signature doit êe correcte
	$signature=decode_base64($signature);

	if ($USE_RSA) {
	if ($USE_RSA_DC_BASED_IMPLEMENTATION) {
		&checkRsaSignatureNoLib(md5_hex($content),$signature,$PUBLIC_KEY);
		}
	else {
	&checkRsaSignature(md5_hex($content),$signature,$PUBLIC_KEY);
		}
	}
		
	# Archiver l'ancien fichier (s'il existe)
	if (-f $plugin) {
		unless (move($plugin,$archive)) {
			# Archive didn't work
			&error("Could not archive last revision. $archive or $plugin must be write protected.");
		}
	}
	
	# Ecrire le nouveau fichier
	open OUTPUT, ">$plugin" || &error ("Cannot write to $plugin")&&return;
	binmode OUTPUT;
	{ local $\; print OUTPUT $content; }
	close OUTPUT;
	
	# Supprimer le fichier de session
	unlink($chunks);
	return "OK";
 }
 
 sub checkRsaSignature() {
	my ($content,$signature,$PUBLIC_KEYfile)=@_;
	eval("use Crypt::RSA");
	&error("Crypt::RSA not present") if ($@);
	my $rsa = new Crypt::RSA; 
	my $PublicKey = new Crypt::RSA::Key::Public (
						Filename => $PUBLIC_KEYfile
					   ) || &error($rsa->errstr());
	my $verifyOK = $rsa->verify (
			Message    => $content, 
			Signature  => $signature, 
			Key        => $PublicKey
		);		
	&error("Security check failed.")&&return unless $verifyOK;
 }
 
 sub checkRsaSignatureNoLib() {
	my ($content,$signature,$PUBLIC_KEYfile)=@_;
	my ($k,$n)=&readKeyFile($PUBLIC_KEYfile);
	$_=rsaCrypt($signature,$k,$n);
	&error("Securiy check failed.")&&return unless ($content eq $_);
} 

sub rsaCrypt() {
	my ($content,$k,$n)=@_;
	local $/;
	$/=unpack('H*',$content);
	my $temp=&createTempFile();
	open DC,">$temp";
	print DC "16dio\U${k}SK$/SM$n\EsN0p[lN*1lK[d2%Sa2/d0<X+d*lMLa^*lN%0]dsXx++lMlN/dsM0<j]dsjxp";
	close DC;
	$_=`$DC_PATH $temp`;
	unlink($temp);
	s/\W//g;
	$_=pack('H*',/((..)*)$/);
 }
 
sub readKeyFile() {
	my($file)=@_;
	open K,$file;
	local $/;
	$_=<K>;
	close K;
	&error("Public key file $file is empty or missing.") unless /\w/;
	s/\W//g;
	my(undef,$k,$n)=split/0x/;
	return ($k,$n);
}
 
 sub contn {
	my ($ID) = @_;
	
	my $chunks = "$SESSIONDIR/$ID.chunks";
	
	# Verification : le fichier doit exister
	&error("Session $ID does not exist.") unless (-f $chunks);
	
	# Lecture du fichier chunks
	open INF, $chunks or &error("Cannot open $chunks: $!");
	binmode INF;
	my $content = do { local $/; <INF> };
	close INF;
	# Supprimer le fichier de session
	unlink($chunks);
	return $content;
 }
 
 sub read_config {
	my $list='';
	foreach (@options) {
		if (defined $$_) {
		$list.="\n" unless $list eq '';
		$list .= "$_=";
		$_=$$_;
		$list.= /\D/?"'$_'":$_;
		}
	}
	return $list;
 }
 
sub write_config {
	my ($CONF,$VARIABLE,@VALUES) = @_;
	
	# Verification : le fichier doit exister
	&error("Configuration is locked.") if ($CONFIG_LOCKED);
	
	# Replace value in config file
	open CF,$CONF or &error("Cannot open $CONF : $!");
	{
		local $/;
		$_=<CF>;
	}
	close CF;
	if (s/^(\s*$VARIABLE\s*=).*/$1 @VALUES/m) {
		open CF, ">$CONF" or &error("Cannot open $CONF : $!");
		print CF;
		close CF;
		return "OK";
	}

	#Add the new variable value
	open CF, ">>$CONF" or &error("Cannot open $CONF : $!");
	print CF "$VARIABLE=@VALUES\n";
	close CF;
	return "OK";
 }
 
 sub readConfig {
	my ($CONF) = @_;
	
	no strict "refs";
	open CF, $CONF or &error("Cannot open $CONF : $!");
	while (<CF>) {
		s/#.*//;
		next unless /\w/;
		$$1=$3 if (/^\s*\$?(\w+)\s*=\s*(['"]?)(.*?)\2;?\s*$/);
	}
	close C;
 }
 
sub run {
	return "Security Error : cannot use this command without RSA security enabled" unless ($USE_RSA || $ALLOW_UNSECURE_COMMAND);
	chdir($BASEDIR);
	return join'',qx!@_!;
}
 
sub download {
	my ($name) = @_;
	$name="$BASEDIR/$name" unless $name=~/^\//;
	open(INF,$name) || &error("Cannot open $name");
	binmode INF;
	$_ = do { local $/; <INF> };
	close INF;
	return $_;
}
 
sub restart {
	my $service=$NRPE_SERVICE_NAME;
	system("sudo service $service restart > /dev/null &");
	return "Reloading '$service' service.";
}
 
sub info {
 	my ($name) = @_;
	$name='*' unless defined $name;
	my $PATH = $name=~/\d$/ ? $ARCHIVEDIR : $BASEDIR;
	my $plugin = "$PATH/$name";
	$plugin=$PUBLIC_KEY if ($name eq 'PUBLIC_KEY');
	$plugin.="/*" if (-d $plugin);
	unless (-f $plugin || $plugin=~/\*/) {
		&error ("$name does not exist in the plugin folder ($PATH)");
		}
	my @FILES = glob($plugin);
	my $multiple = @FILES>1;
	my $output;
	$output = "#HEADER# Name\tSize(bytes)\tVersion\tSignature\n" if $multiple;
	foreach my $file (@FILES) {
		next if -d $file;
		my $size = -s $file;
		# Lecture du numero de version
		open INF,$file || &error("Cannot open $name");
		binmode INF;
		$_ = do { local $/; <INF> };
		close NF;
		my $Version="";
		$Version=$1 if /(?:Version|Revision)\W*(\d[\d\.]*[a-z]?\b)/i;
		my $MD5=md5_hex($_);
		$name=$file; $name=~s/$PATH\///;
		if ($multiple) {
			$output .= "$name\t${size}\t$Version\t$MD5\n";
		} else {
			$output .= "$name \t${size} bytes \tVersion $Version \tSignature : $MD5\n";
		}
	}
	return $output;
 }
 
 # Service implementation
 
sub service {
	$SERVICE = 1;
	&read_order_list;
	while (1) {
		my @orders = &read_channel;
		foreach my $order (@orders) {
			&run_order($order);
			}
		sleep(5);
	}
}

# Reads the "order list" file, which maintains the last nown states of the orders (running/done/pending/sent)
sub read_order_list {
	
}

sub run_order {
	my ($order)=@_;
	my ($id,$dest,$mission,$prereq,@args)=split/\|/,$order;
	run_command($mission,@args);
}

# Looks for orders in the given channel
sub read_channel {
	my $channel="$SESSIONDIR/order";
	if (-f $channel) {
		open CH, $channel;
		my $order = <CH>;
		close CH;
		unlink $channel;
		return ($order);
	}
	return (  );
}

sub createTempFile() {
	my $ID=&newChunkId();
	return "$SESSIONDIR/$ID.chunks";
}

sub newChunkId() {
	my $ID;
	do {
		$ID = int(rand(100000));
	} until(! -f "$SESSIONDIR/$ID.chunks");
	return $ID;
}
 
 sub error() {
	my ($msg)=@_;
	$\=$/;
	print $msg;
	exit(1) unless $SERVICE;
 }
 
 sub output() {
	my ($msg)=@_;
	my $POSTFIX = "___Cont:0000000___";
	if (length($msg) >= $OUTPUT_LIMIT) {
		my $ID = &newChunkId();
		$POSTFIX =~ s/0+/$ID/;
		my $cutAt = $OUTPUT_LIMIT - (10+length $POSTFIX);
		
		my $pre_msg = substr($msg,0,$cutAt);
		my $post_msg = substr($msg,$cutAt-1);

		my $file = "$SESSIONDIR/$ID.chunks";
		&write_to_file($file ,$post_msg);
		
		$msg = $pre_msg . $POSTFIX;
	}
	local $\;
	print $BASE64_TRANSFERT ? "b*64_".encode_base64($msg)."_b64" : $msg;
	exit(0);
 }
 
 sub mkpath() {
	my ($path)=@_;
	my @path = split /[\/\\]/,$path;
	my $path='';
	foreach (@path){
		$path.=$_;
		if ($path=~/\w/) { -d $path || mkdir($path) || return 0 }
		$path.='/';
	}
	1;
 }
