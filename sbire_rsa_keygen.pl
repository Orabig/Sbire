#!/usr/bin/perl

####################
#
# sbire_keygen.pl
#
# @Version 0.1
# 
# NRPE plugins update/manage master script (keygen)
#
# Usage : 
#    sbire_keygen.pl
#
####################

my $pubkey = "/usr/local/nagios/bin/sbire_key.pub";
my $privkey = "/usr/local/nagios/bin/sbire_key.private";

die "File already exist" if (-f $pubkey || -f $privkey);
	
use strict;

use Crypt::RSA;
 
   my $rsa = new Crypt::RSA; 

   $_=`hostname`; chomp;
   my $identity = $_;
   
   print "Generation...\n";
   my ($public, $private) = 
        $rsa->keygen ( 
            Identity  => $identity,
            Size      => 2048,  
        ) or die $rsa->errstr();

	print "Write $pubkey\n";
   $public->write ( Filename => $pubkey)|| die $rsa->errstr();
	print "Write $privkey\n";
   $private->write ( Filename => $privkey)|| die $rsa->errstr();
   print "Done\n";
