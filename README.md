Welcome to Sbire project
========================

Introduction
------------

Sbire is a set of scripts whose aim is to help deploy, modify and maintain remote NRPE scripts.

Sbire at a glance
-----------------

(History : Sbire-server has been installed and setup on a Linux machine called `master`. Nrpe and Sbire-client has been installed on several Linux and Windows servers, called `Venus`, `Mars`, `Saturn`, `Neptun` and so on...)

    # This command will "connect" to all the known remote servers
    
    user@master:~$ connect all
    VENUS    sbire.pl Version 0.9.26   (linux, RSA:pub=)
    MARS     sbire.pl Version 0.9.26   (linux, RSA:pub=)
    SATURN   sbire.pl Version 0.9.26   (Win32, RSA:pub=)
    ...

    # This will ask for the version of a NRPE check

    user@master:~$ c info -n my_nagios_plugin.pl --csv
    VENUS    my_nagios_plugin.pl    70426 bytes     Version 1.2    Signature : dbb3e5d3ca5c21788f9bb1e47e409fcc
    MARS     my_nagios_plugin.pl    72340 bytes     Version 1.3    Signature : 0cc45e8ec072b0187c5b7dad0761d3d9
    SATURN   my_nagios_plugin.pl    70426 bytes     Version 1.2    Signature : dbb3e5d3ca5c21788f9bb1e47e409fcc

    # Ok, the plugin seems more recent on MARS, lets take it locally...
    
    user@master:~$ connect MARS
    MARS     sbire.pl Version 0.9.26   (linux, RSA:pub=)
    user@master:~$ c download -n my_nagios_plugin.pl > /tmp/my_nagios_plugin.pl
    
    # ... then push it to the other servers.
  
    user@master:~$ connect all
    (...)
    user@master:~$ c upload --csv -n my_nagios_plugin.pl -f /tmp/my_nagios_plugin.pl
    VENUS   OK. 72340 bytes uploaded.
    MARS    Skipped. Files are identical
    SATURN  OK. 72340 bytes uploaded.
    (...)
    
    # By the way, would you be able to run a command on several server at once ?
    
    user@master:~$ r ls -l
    VENUS  total 8
    VENUS  -rwxrwsr-x 2 nagios nagios 72340 May 19 10:30 my_nagios_plugin.pl
    VENUS  -rwxrwsr-x 2 nagios nagios 12668 May 12 11:02 check_fs.pl
    VENUS  -rwxrwsr-x 2 nagios nagios 14611 May 11 11:35 check_disk.pl
    VENUS  -rwxrwsr-x 2 nagios nagios 24587 May 15 16:48 sbire.pl
    MARS   total 8
    MARS   -rwxrwsr-x 2 nagios nagios 72340 May 19 10:20 my_nagios_plugin.pl
    MARS   -rwxrwsr-x 2 nagios nagios 12668 May 19 10:20 check_fs.pl
    MARS   -rwxrwsr-x 2 nagios nagios 14655 May 19 10:22 check_disk.pl
    MARS   -rwxrwsr-x 2 nagios nagios 24587 May 16 10:22 sbire.pl
    (...)
    
    # Or launch an NRPE script for testing ?
    
    user@master:~$ r nrpe -a check_disk -- -n /tmp
    -----------------------
    | VENUS (12.34.56.78) |
    -----------------------
    OK | /tmp=62%,80,90
  
    ----------------------
    | MARS (12.34.56.79) |
    ----------------------
    OK | /tmp=35%,80,90
    
    (...)

    # Or even modify your NRPE configuration file ...
    
    user@master:~$ c config -n /etc/nagios/nrpe.cfg -- 'command[new_check] /usr/bin/perl my_new_check.pl \$ARG1\$'
    -----------------------
    | VENUS (12.34.56.78) |
    -----------------------
    OK (Added '/usr/bin/perl my_new_check.pl $ARG1$')
  
    ----------------------
    | MARS (12.34.56.79) |
    ----------------------
    OK (Added '/usr/bin/perl my_new_check.pl $ARG1$')
    
    (...)
    
    # ... upload the check script ...
    
    user@master:~$ c upload -n my_new_check.pl -f ./DEV/new_script/my_new_check.pl
    (...)
    
    # ... And finally restart the NRPE service ?

    user@master:~$ r sudo /etc/init.d/nagios-nrpe-service restart
    (...)
    
    # Did you notice you just deployed a brand new check on several servers with only 3 command lines ?
    
Install
-------

Server side :

NRPE plugin must be present on server-side. To install check_nrpe plugin, there is an install script that you can launch with :

    curl -sSL sbi.re/install_nrpe | sudo bash

To install sbire_master (which is the server-side of sbire), just type

    curl_sSL sbi.re/install_server | sudo bash



Presentation
------------

Atm, there are 3 scripts :

* *sbire.pl*

  It's the main script, which must be placed on remote NRPE servers (usually inside the folder
  containing the plugins).

* *sbire_master.pl*

  It's the command script, which is supposed to be run on a command line. It's controls `sbire.pl`
  remotely, whith the help of a standard `check_nrpe` call.

* *sbire_rsa_keygen.pl*

  It's an utility which generates a couple of private/public keys, which can be used when RSA security-based
  transfert protocol are activated between `sbire.pl` and `sbire_master.pl`.

Install
-------

### Remote NRPE server install

This procedure assumes that NRPE daemon/service is installed and running on the remote server. You can check it by running
`check_nrpe -H <IP>` on the master server. This command should be able to connect to the NRPE server (on the given `<IP>` adress) which will print the NRPE version.

1. sbire.pl must be copied on the remote server. You should put it in a directory which will contain the plugin scripts. (Here,
   it will be `/opt/nagios/libexec/`.)

2. Edit `nrpe.cfg` file and add following line (adjust the paths) :

   > command[sbire]=/opt/nagios/libexec/sbire.pl /opt/nagios/etc/sbire.conf $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ 2>&1

   You can also add the following line :

   > include=/opt/nagios/libexec/local.nrpe.cfg

   Which will define a local configuration file that you will use to add new plugins.

3. Create the configuration file (given on the command line above)

   > # /opt/nagios/etc/sbire.conf :
   > 
   > (...)

4. (If the remote server is Linux) : Type the following line :

   > echo "nagios ALL = NOPASSWD: `which service`" >>/etc/sudoers

   which will allow the `nagios` user to restart the NRPE service (which will be very helpful)

5. Restart the NRPE server.

   > sudo service nrpe restart

Usage
-----

To check if configuration is correct, run :

> ./sbire_master.pl -H <IP>

It should return :

> sbire.pl Version 0.9.2


To transfert or update a NRPE plugin, write :

> `./sbire_master.pl` -H <IP> -c update -n <remote> -f <local>

Where : <remote> is the name of the NRPE script (in the remote folder)
        <local> is the filename of the script to transfert

This will do the following :

1. If <remote> and <local> are identical, nothing is done (an MD5 comparison is performed)
2. <local> is sent to the NRPE server in a temporary folder (SESSION_FOLDER)
3. If a <remote> file already exist, then it's archived
4. The new <remote> file is written/replaced.

