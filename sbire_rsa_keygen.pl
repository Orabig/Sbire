#!/usr/bin/perl

####################
#
# sbire_rsa_keygen.pl
#
# @Version 0.2
# 
# NRPE plugins update/manage master script (keygen)
#
# Usage : 
#    sbire_keygen.pl
#
####################

my $PATH=shift @ARGV;
$PATH="." unless defined $ATH;

my $pubkey = "$PATH/sbire_key.pub";
my $privkey = "$PATH/sbire_key.private";

die "$pubkey File already exist" if (-f $pubkey);
die "$privkey File already exist" if (-f $privkey);
	
use strict;

use Crypt::RSA;
 
   my $rsa = new Crypt::RSA; 

   $_=`hostname`; chomp;
   my $identity = $_;
   
   print "Generation...\n";
   my ($public, $private) = 
        $rsa->keygen ( 
            Identity  => $identity,
            Size      => 1024,  
        ) or die $rsa->errstr();
		
	print "Conversion to hex.\n";
	use bigint;
	my ($n,$d,$e);
		$\=$/;
		$n = Math::BigInt->new($private->{'private'}->{'_n'});
		$d = Math::BigInt->new($private->{'private'}->{'_d'});
		$e = Math::BigInt->new($private->{'private'}->{'_e'});
	
	open PUB, ">$pubkey" || die "Cannot open $pubkey for writing";
	print PUB $e->as_hex();
	print PUB $n->as_hex();
	close PUB;
	open PRI, ">$privkey" || die "Cannot open $privkey for writing";
	print PRI $d->as_hex();
	print PRI $n->as_hex();
	close PRI;
	
   print "Done\n";
