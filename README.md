Welcome to Sbire project
========================

Introduction
------------

Sbire is a set of scripts whose aim is to help deploy, modify and maintain remote NRPE scripts.

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

