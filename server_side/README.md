Fast and easy installation on client
====================================

Prerequesites
-------------

This installer now only works on Linux distribution using 'systemctl' or 'service' to start/stop services.

How to install Sbire (client-side) on Linux
-------------------------------------------

* Make sure that NRPE is up and running (TODO : write an installer)
* Perl should be installed
* type the following :

    curl -sSL sbi.re/install | sudo bash

* enjoy...

(Optional, if the client is Linux) : Type the following line :

    echo "nagios ALL = NOPASSWD: `which service`" >>/etc/sudoers

which will allow the `nagios` user to restart the NRPE service (which will be very helpful)

How to install Sbire (client-side) on Windows
---------------------------------------------

* Install NSClient++ ( http://www.nsclient.org/ )
* Install Perl ; this could be either Strawberry ( http://strawberryperl.com/ ) or ActivePerl ( http://www.activestate.com/activeperl/downloads )
* Download sbire.pl ( http://sbi.re/sbire.pl ) and drop it into <NSCP++>/scripts directory.
* Append the following line to nsclient.ini

    (path)\perl.exe (path)\sbire.pl (path)\sbire.ini $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ $ARG6$ $ARG7$ 