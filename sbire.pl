#!/usr/bin/perl

my $Version= 'Version 0.9.7';

####################
#
# sbire.pl
#
# 
# Remote control script
#
# Usage :
#
#    sbire.pl <CFG> send newfile 
#		Creates a new session ID for file sending
#
#    sbire.pl <CFG> send newfile 
#		Creates a new session ID for file sending
#
#    sbire.pl <CFG> send <ID> <chunk_b64> <offset>
#		Send a new chunk (part of a new file) into the quarantine directory
#
#    sbire.pl <CFG> update <name> <sessionID> <signature>
#		Creates or updates a plugin/file with the previously sent file. If sessionID has ".z" suffix, then the file is zipped and must be unpacked.
#
#    sbire.pl <CFG> chmod <name> <chmod> 
#		Creates or updates a plugin/file with the previously sent file
#
#    sbire.pl <CFG> info <name>
#		Gets informations about a plugin.file (size, checksum and version if any). If name is omitted, then '*' is assumed.
#
#    Note : When the output of a command is longer than $OUTPUT_LIMIT (def. 1024), then it's truncated and ends with ___Cont:<id>___. The following
#           of the output may then be retreived with the following command.
#
#    sbire.pl <CFG> continue <sessionID>
#		Gets the output store in the given sessionID. (see above note)
#
#    sbire.pl <CFG> service
#       Loops and waits for "orders" to execute. The process thus runs indefinitely. It looks for data sources
#       defined in a "channel" list for orders documents, that have the following structure : {"ID":"<int>", 
#       "type":"<transfert|exec|info>", "file":"<base64_encrypted_content>", "name":"<filename>"}
#
####################

 use MIME::Base64;
 use File::Copy;
 use Digest::MD5 qw(md5_hex);
 
 use strict;
 
 # Definition du fichier de configuration
 our ($pubkey,$SESSIONDIR,$ARCHIVEDIR,$PLUGINSDIR,$USE_RSA,$OUTPUT_LIMIT);
 $OUTPUT_LIMIT = 1024;
 our ($SERVICE);
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
 
 if ($COMMAND eq 'service') 
	{ $SERVICE=1; &service; }
else 
	{ run_command($COMMAND,@ARGV); }
	
 exit(0);

sub run_command {
	my ($COMMAND,@ARGS)=@_;
	if ($COMMAND eq 'send') 
	{ &output(&send(@ARGS)) }
 elsif ($COMMAND eq 'update') 
	{ &output(&update(@ARGS)) }
 elsif ($COMMAND eq 'chmod') 
	{ &output(&chmod(@ARGS)) }
 elsif ($COMMAND eq 'info') 
	{ &output(&info(@ARGS)) }
 elsif ($COMMAND eq 'run') 
	{ &output(&run(@ARGS)) }
 elsif ($COMMAND eq 'continue') 
	{ &output(&contn(@ARGS)) }
 else 
	{ &error("Command '$COMMAND' unknown.") }

}

sub send {
	my $ID = shift;
	if ($ID eq 'newfile') {
		# Creation d'un nouvel ID de session
		$ID = &newChunkId();
		return $ID;
		return;
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
	my $plugin = "$PLUGINSDIR/$name";
	
	# Verification : le fichier doit exister
	&error("Session $ID does not exist.") unless (-f $chunks);
	
	# Trouver un numero libre pour l'archive
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
		$content = uncompress($content);
		}
	
	# Verification : la signature doit être correcte
	
	$signature=decode_base64($signature);
	
	if ($USE_RSA) {
		eval("use Crypt::RSA");
		my $rsa = new Crypt::RSA; 
		my $PublicKey = new Crypt::RSA::Key::Public (
							Filename => $pubkey
						   ) || &error($rsa->errstr());
		my $verify = $rsa->verify (
				Message    => $content, 
				Signature  => $signature, 
				Key        => $PublicKey
			) || &error("Security check failed");		
		&error("Security check failed")&&return unless $verify;
	}
		
	# Archiver l'ancien fichier (s'il existe)
	-f $plugin && ( move($plugin,$archive) || &error("Cannot backup last revision. Is $archive writtable ?") );
	
	# Ecrire le nouveau fichier
	open OUTPUT, ">$plugin" || &error ("Cannot write to $plugin")&&return;
	binmode OUTPUT;
	{ local $\; print OUTPUT $content; }
	close OUTPUT;
	
	# Supprimer le fichier de session
	unlink($chunks);
	return "OK";
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
 
sub run {
	my ($name) = @_;
	return "Security Error : cannot use this command without RSA security enabled" unless ($USE_RSA);
	return `$name 2>&1`;
}
 
sub chmod {
 	my ($name,$mod) = @_;
        $_ = "$PLUGINSDIR/$name";
	&error("$name does not exist") unless -f;
	`chmod $mod $_`;
	my $result="";
	$result .= (-r) ? 'r':'-';
	$result .= (-w) ? 'w':'-';
	$result .= (-x) ? 'x':'-';
	return "$name : $result";
}
 
sub info {
 	my ($name) = @_;
	$name='*' unless defined $name;
	my $PATH = $name=~/\d$/ ? $ARCHIVEDIR : $PLUGINSDIR;
	my $plugin = "$PATH/$name";
	unless (-f $plugin || $plugin=~/\*/) {
		&error ("$name does not exist");
		}
	my @FILES = glob($plugin);
	my $multiple = @FILES>1;
	my $output;
	$output = "Name\tSize(bytes)\tVersion\tSignature\n" if $multiple;
	foreach my $file (@FILES) {
		next if -d $file;
		my $size = -s $file;
		# Lecture du numero de version
		open INF,$file || &error("Cannot open $name");
		binmode INF;
			$_ = do { local $/; <INF> };
			close INF;
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

# Reads the "order list" file, which maintains the last known states of the orders (running/done/pending/sent)
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

sub newChunkId() {
	my $ID;
	do {
		$ID = int(rand(100000));
	} until (! -f "$SESSIONDIR/$ID.chunks");
	return $ID;
}
 
 sub error() {
	my ($msg)=@_;
	print $msg;
	exit(1) unless $SERVICE;
 }
 
 sub output() {
	my ($msg)=@_;
	my $POSTFIX = "___Cont:0000000___";
	if (length($msg) >= $OUTPUT_LIMIT) {
		my $ID = &newChunkId();
		$POSTFIX =~ s/0+/$ID/;
		my $cutAt = $OUTPUT_LIMIT - (1+length $POSTFIX);
		
		my $pre_msg = substr($msg,0,$cutAt);
		my $post_msg = substr($msg,$cutAt);

		my $file = "$SESSIONDIR/$ID.chunks";
		&write_to_file($file ,$post_msg);
		
		$msg = $pre_msg . $POSTFIX;
	}
	local $\;
	print $msg;
	exit(0);
 }
 
 
