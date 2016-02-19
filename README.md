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

* Server side :

NRPE plugin must be present on server-side. To install check_nrpe plugin, there is an install script that you can launch with :

    curl -sSL sbi.re/install_nrpe | sudo bash

To install sbire_master (which is the server-side of sbire), just type

    curl -sSL sbi.re/install_server | sudo bash

* Client side *(Where you will type your commands)* :

**TODO : Find a Linux expert who could tell me if there's a better place for this**

Extract this repository to /opt/adm/sbire

	mkdir -p /opt/adm
    git clone https://github.com/Orabig/Sbire.git sbire
	
Add the following into your `.bashrc` file

    if [ -f /opt/adm/sbire/etc/.bash_aliases ]; then
            source /opt/adm/sbire/etc/.bash_aliases
    fi


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


  
Usage
-----

You should create /opt/adm/sbire/etc/server_list.txt (there's a sample file) and add you servers IP adresses and aliases.

To check if configuration is correct, just type :

    $ connect all

It should return :

    $ connect all
	ALIAS1     sbire.pl Version 0.9.29  (linux, RSA:pub=/opt/nagios/etc/sbire_rsa.pub)
	ALIAS2     sbire.pl Version 0.9.29  (linux, RSA:pub=/opt/nagios/etc/sbire_rsa.pub)
	...

To run sbire commands on a specific server, type

    $ connect ALIAS1
	ALIAS1     sbire.pl Version 0.9.29  (linux, RSA:pub=/opt/nagios/etc/sbire_rsa.pub)
	$ r pwd
	ALIAS1     /usr/lib/nagios/plugins
	
You may also connect to serveral server at once with

    $ connect ALIAS1,ALIAS3,(...)
	
Or build a server list in a file 'aliaslist', and use

    $ connect @aliaslist


* The following aliases are available :

Alias              | Description                
------------------ | ------------------------------
s  | Run sbire on every connected servers
s -c &lt;command> ... | Run a sbire command among upload, download, run, info, config, nrpe
c &lt;command> ... | Alias to `s -c &lt;command> ...`
r &lt;cmdline> -- ... | Alias to `s -c run -n &lt;cmdline> -- ...` : will launch the given cmdline on servers

* Some common arguments may be used

Argument         |  Description
---------------- | --------------
--csv | Output the result in CSV like (no server info blocks and each line is prefixed by the server alias)
--split <file> | Each unique output is saved in a separate `file.1.out`, `file.2.out`... file, and the aliases are stored in `file.1.lst`....
--local (with `info` command) | run sbire locally to get the version info about a local file
--local (with `run` command) | run a command line locally **for each connected server**. Useful with the following macros : __NAME__ and __TARGET__ (the alias name and IP adress resp.)

Examples :

    $ r --local echo __NAME__ IP is __TARGET__
	$ c download -n myplugin -f myplugin.__NAME__
	$ c download -n myplugin --split myplugin
    $ r --local ping __TARGET__ -c 1
	
	
Commands
--------



To transfert or update a NRPE plugin, write :

> c upload -n &lt;remote> -f &lt;local>

Where : &lt;remote> is the name of the NRPE script (in the remote folder)
        &lt;local> is the filename of the script to transfert

This will do the following :

1. If &lt;remote> and &lt;local> are identical, nothing is done (an MD5 comparison is performed)
2. &lt;local> is sent to the NRPE server in a temporary folder (SESSION_FOLDER)
3. If a &lt;remote> file already exist, then it's archived
4. The new &lt;remote> file is written/replaced.

