#Présentation#

Sbire est un outil client/serveur, permettant via NRPE de maintenir les configurations, d’exécuter des commandes à distances ou de transférer des fichiers. 
Son fonctionnement est basé sur 3 scripts
* sbire.pl coté serveur (la machine à interroger / piloter)
* sbire_master.pl et sb_sergeant coté client (le poller depuis lequel on lance la commande)
			

Le rôle de sbire_master est d’utiliser le protocole NRPE  pour appeler sbire à distance sur le serveur.
Le rôle de sb_sergeant est de permettre d’exécuter la même requête sur plusieurs serveurs à la fois en une seule commande, en se basant sur un fichier contenant la liste des serveurs et leur configuration (protocole à utiliser). Il est donc conseillé d’utiliser systématiquement sb_sergeant qui est plus simple d’utilisation que sbire_master (à qui il faut passer tous les paramètres de connexion).


Les rôles de sbire sont 
* Maintenir la supervision des agents NRPE (Gestion des configuration)
* Deployer de nouveaux plugins ou de nouvelles versions de ceux-ci
* Controler les niveaux de versions, de l'agent, des fichiers de configurations, des plugins. (CheckSum).
* Transferer dans les deux sens des fichiers de ou dans l'agent NRPE
* Executer des commandes

Toutes ces actions peuvent etre effectuées unitairement ou en masse.  
	
Au-dessus du protocole utilisé (NRPE), sbire peut utiliser le protocole RSA pour signer les données envoyées et reçues avec un système de clés (privées coté client, les clés publiques étant déposées sur les serveurs distants).
Ce protocole est facultatif, mais La mise en place de cette sécurité est hautement conseillée car elle permet d’assurer qu’un serveur non autorisé ne peut pas utiliser sbire. 

Via NRPE SBIRE a été testé sur different agent NRPE , il est fonctionnel sur des version 2.9 ou supérieur. 

Les OS suivants ont été testés (PERL =>5.8)
* Unix/Linux
* Aix 5/6
* HPUX 10/11
* Solaris 9/10/11
* Windows 2000/2003/2008/2012 (protocole NRPE de l'agent NSCLIENT)



#Install#

##Partie MAITRE##

###Pré-requis :### 

	check_nrpe 
	PERL => 5.8
	
La partie maitre sera installé par défaut dans notre exemple dans le répertoire /usr/local/Sbire. 

├── sbire_master.pl
├── sbire_rsa_keygen.pl
├── sb_sergeant.pl
└── etc
       ├── sbire_master.conf   <== Parametre sbire_master.pl 
       ├── sb_sergeant.cfg     <== Parametre sb_sergeant.pl 
       ├── server_list.txt     <== Definition de tous les hosts géré par sbire 
       ├── clientX-windows.lst <== Liste spécifiques au client X et ses serveurs sous Windows
       ├── clientX-linux.lst   <== Liste spécifiques au client X et ses serveurs sous Linux
       └── clientY.lst		   <== Liste spécifiques au client Y pour tous ses serveur

==Partie ESCLAVE==

===Pré-requis :=== 

	NRPE >= 2.9 compilé avec l'option --enable-args  
	PERL >= 5.8
	
Au préalable vous avez installé correctement l'agent NRPE sur le serveur distant à superviser.
activez dans le fichier nrpe.cfg l'option dont_blame_nrpe=1 pour accepter le passage des arguments. 

sbire.pl doit etre copié sur le serveur à superviser . 
Vous devriez le placer dans le repertoire  contenant les plugins de supervisions. (Dans notre exemple /usr/nagios/libexec/.)

Editez nrpe.cfg et rajoutez les lignes suivantes (adaptez les path à vos install ) :

   command[sbire]=/usr/local/nagios/libexec/sbire.pl /usr/local/nagios/etc/sbire.conf $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ 2>&1

Il est conseillé par la suite de séparer les commandes dans un fichier à part :

   include=/usr/local/nagios/etc/nrpe-command.cfg

Cela permettra de ne modifier que cette partie pour ajouter/effacer/modifier les plugins. 

Créer le fichier de configuration sbire.conf 


   /usr/local/nagios/etc/sbire.conf 
   
   SESSIONDIR = /usr/local/nagios/tmp/sbire
   ARCHIVEDIR =/usr/local/nagios/tmp/sbire/archive
   BASEDIR = /usr/local/nagios
   PUBLIC_KEY = /usr/local/nagios/etc/sbire_rsa.pub
   NRPE_SERVICE_NAME = nrpe
   USE_RSA_DC_BASED_IMPLEMENTATION=1
   USE_RSA = 0
   ALLOW_UNSECURE_UPLOAD = 1
   CONFIG_LOCKED = 0
(...)


=Configuration= 

==serverlist.txt==


Une fois la partie maitre et la partie Esclave installé il faut préparer le fichier server_list.txt pour les hosts intérrogeable par sbire ainsi que les listes spécifiques.
Ce fichier contient donc la liste de tout les serveurs supervisés et leurs parametres de connexion (Port NRPE , PARAMETRE SSL

   # Server list
   # Alias	IP/Name		Protocol
   
   # DEFAULT ATTRIBUTES :
   
   # DEFINE CHECK_NRPE SSL SWITCH ( check-nrpe -n -H SERVERX ) 
   	NRPE-USE-SSL	0
   # DEFINE COMMUNICATION PORT FOR NRPE AGENT	
   	   NRPE-PORT	5666
   
   
   # SERVER DEFINITION
   
   SERVER1 	192.168.1.1 	NRPE
   SERVER2		192.168.100.2	NRPE
     	NRPE-PORT	3181
   SERVER3		192.168.100.2	NRPE
     	NRPE-SSL	1
   SERVER4		192.168.100.2	NRPE
     	NRPE-PORT	3181
     	NRPE-SSL	1
		

Crétion d'un filtre par liste. 

liste.txt
   SERVER1
   SERVER4

==Utilisation==

(les scripts sbire.pl et sbire_master.pl n’étant pas destinés à être lancés manuellement, il n’est question ici que de la syntaxe d’utilisation de sb_sergeant.pl)

Le premier argument est obligatoire, et peut prendre les valeurs suivantes :

   ·       all : la commande sera exécutée sur tous les serveurs du fichier de configuration server_list.txt
   ·       <NOM> : la commande sera exécutée sur le serveur <NOM>.
   ·       @<liste> : la commande sera exécutée sur les serveurs contenu dans le fichier <liste> (un nom de serveur par ligne)

 L’argument –c permet ensuite de définir la commande à lancer. Si aucune commande n’est définit, sb_sergeant se contente d’interroger sbire qui lui renvoie son numéro de version.
 Cela permet de vérifier que la configuration et la connexion sont correctes.

./sb_sergeant.pl SERVER(vide)

Renvoie le numéro de version de sbire.pl (Le Type d'OS et la valeur de USE_RSA et le PATH vers la Clé publique)

./sb_sergeant.pl SERVER -c (vide)
Affiche la liste des commandes pouvant etre passée a sbire.
 
== OPTIONS : -c info ==
./sb_sergeant.pl SERVER -c info

Récupère les informations la taille, version et signature du/des fichier(s) distant(s) :
	du répertoire de base 
	avec l'option (–n) d'un fichier dans l'agent


 
== OPTIONS : -c download ==
./sb_sergeant.pl SERVER -c download

Copie le fichier distant (-n) vers le fichier local (-f) ou STDOUT
    Exemple :
	./sb_sergeant.pl SERVER -c download -n etc/nrpe.cfg -f nrpe.cfg-SERVER
	
	Exemple
	---------------------------
   |SERVER (192.168.0.XX)     |
    ---------------------------
   ....OK
   
 Le fichier à été récupéré via NRPE en tant que nrpe.cfg-NRPE
  
== OPTIONS : -c upload ==

./sb_sergeant.pl SERVER -c upload 

Copie le fichier local (-f) vers le fichier distant (-n)

    Exemple :
	./sb_sergeant.pl SERVER -c upload -n etc/nrpe.cfg -f nrpe.cfg-SERVER
	
	Exemple
	---------------------------
   |SERVER (192.168.0.XX)     |
    ---------------------------
   ....OK
   
== OPTIONS : -c run ==
./sb_sergeant.pl SERVER -c run -- commande

Exécute une commande à distance (--)

./sb_sergeant.pl SERVER -c config -- "PARAM XX"

Change la valeur d’une option dans le fichier de configuration distant sbire.conf

./sb_sergeant.pl SERVER -c options

Affiche la liste des paramètres distants

./sb_sergeant.pl SERVER -c restart

Relance le service NRPE (serveur distant Unix seulement pour les agents en daemon, pas xinetd)


Configuration

Chaque script sbire distant gère son propre fichier de configuration, qui contient les options qui lui sont propres. 
Il est possible de modifier la valeur de ces options avec la commande « -c config »

[root@POLLER sbire-master]# ./sb_sergeant.pl SERVER -c config -- OPTION valeur

 

Nom

défaut

Description

BASE64_TRANSFERT

1 (=vrai)

Indique si les données envoyées au maitre par sbire doivent être encodées en Base64. Ceci permet d’éviter l’interprétation des données par NSClient++ qui interprète le caractère |.

OUTPUT_LIMIT

640

Permet de limiter le nombre de caractères à envoyer au maitre, afin de rester compatible avec le protocole NRPE.

USE_RSA

0 (=faux)

Indique si les fichiers et les commandes envoyés par le maitre doivent être signés.

PUBLIC_KEY

-

Le chemin vers le fichier de clé publique coté esclave, qui permet de vérifier la signature des fichiers et des commandes.

USE_RSA_DC

_BASED_IMPLEMENTATION

0 (=faux)

Permet d’utiliser “dc” pour calculer la signature RSA en cas d’absence du module Perl Crypt ::RSA.

DC_PATH

‘dc’

Le chemin vers le programme “dc”.

ALLOW_UNSECURE_UPLOAD

0

Permet d’utiliser la fonction upload même si USE_RSA=0

ALLOW_UNSECURE_COMMAND

0

Permet d’utiliser la fonction run même si USE_RSA=0

NRPE_SERVICE_NAME

‘nrpe’

Le nom du service NRPE, qui est relancé quand on appelle la commande restart (esclave Linux uniquement)

CONFIG_LOCKED

1

Si =1, alors il est impossible de modifier les options.

SESSIONDIR

-

Le répertoire où sont stockés les fichiers de session

ARCHIVEDIR

-

Le répertoire où sont stockés les versions successives des fichiers uploadés

BASEDIR

-

Le répertoire qui sert de base aux chemins relatifs.


3. FAQ : Erreurs connues et résolutions

Message d’erreur :

Security Error : cannot use this command without RSA security enabled

Explication :

Pour des raisons de sécurité, sbire refuse de lancer une commande sans que l'authentification RSA soit activée entre le maitre et l'esclave.

Résolution :

Il suffit d’activer le protocole RSA (config USE_RSA 1) ou de permettre l’utilisation d’une commande sans RSA (sbire version 0.9.15 ou plus : config ENABLE_UNSECURE_COMMAND 1)

[root@POLLER   sbire-master]# ./sb_sergeant.pl SERVEUR -c config -e "USE_RSA 1"

---------------------------

| SERVEUR (194.2.53.44) |

---------------------------

OK

 

 

Message d’erreur :

Configuration is locked

Explication :

Soit la configuration a été "lockée" sur l'esclave, soit sbire a été déployé sans fichier de configuration, et donc la configuration est LOCKED par défaut. Dans tous les cas, la configuration ne peut plus être modifiée par le maitre.

 

Résolution :

Se connecter manuellement à l'esclave, et modifier le fichier de configuration pour ajouter CONFIG_LOCKED = 0

 

Message d’erreur :

Crypt::RSA not present

Explication :

Le module perl Crypt ::RSA n'est pas présent sur le serveur

Résolution :

Il est possible de remplacer ce module (difficile à installer) par le programme GNU dc (ou bc sur Windows), qui permettra de calculer le cryptage par clé RSA. Pour cela, il faut activer l'option USE_RSA_DC_BASED_IMPLEMENTATION :

 

# ./sb_sergeant.pl SERVEUR -c config -e "USE_RSA_DC_BASED_IMPLEMENTATION 1"

---------------------------

| SERVEUR (194.2.53.44) |

---------------------------

OK

 

 

Message d’erreur :

Public key file is empty or missing

Explication :

La clé publique n'a pas été déposée sur le serveur distant

Résolution :

Déposer la clé avec la commande :

(TODO : rédiger la procédure)

Il est aussi possible de désactiver tout simplement la sécurité RSA.

# ./sb_sergeant.pl HPLAVIL04 -c config -e "USE_RSA 0"

---------------------------

| HPLAVIL04 (194.2.53.44) |

---------------------------

OK

 

 

Message d’erreur :

The command (…) returned an invalid return code: 255

Explication :

Le fichier distant sbire.pl est corrompu, endommagé ou manquant.

Résolution :

Il faut se connecter manuellement au serveur, et réparer le fichier ou relancer l'installation. Merci de sauvegarder l'historique des commandes envoyées à ce serveur, afin de trouver l'origine du problème en vue d'une correction.

 

Message d’erreur :

Configuration error : PLUGINSDIR (C:/BT-NSCP64/sbire_temp) does not exist or is not writable

Explication :

La configuration de sbire coté serveur est incorrecte. Il peut s’agir d’un fichier de configuration 64 bits qui a été déployé sur une installation 32 bits (problème constaté lors du déployement ASFA)

Résolution :

Il faut se connecter manuellement au serveur, et réparer le fichier ou relancer l'installation. La version 0.9.16 de sbire devrait normalement corriger ce message d’erreur si le cas venait à se reproduire.

 

Message d’erreur :

Can't locate Config/Simple.pm in @INC (…)

Explication :

Les scripts (coté client) de sbire ont été installés, mais il manque la bibliothèque Perl Config::Simple.

Résolution :

Mettre à jour sb_sergeant dans la version 0.9.6 minimum, qui n’utilise plus cette dépendance

 

Message d’erreur :

Résultat d'un commande ressemble à

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

b*64_IFZvbHVtZSBpbiBkcml2ZSBDIGhhcyBubyBsYWJlbC4KIFZvbHVtZSBTZXJpYWwgTnVtYmVyIGlz

IDBDMjktOUUzQgoKIERpcmVjdG9yeSBvZiBDOlxCVC1OU0NQNjQKCjA4LzAxLzIwMTMgIDEyOjI4

IFB(...)

 

Explication :

La taille du "packet" d'échange avec sbire est trop grand par rapport à la configuration NRPE. Le packet encodé en Base64 ne se décode donc pas correctement.

Résolution :

Baisser la valeur de l’option OUTPUT_LIMIT (positionnée à 1024 sur certains serveurs, ce qui est trop haut pour l’implémentation dans NSclient++ du protocole NRPE)

 ./sb_sergeant.pl Acronis-ASN -c config -- OUTPUT_LIMIT 640

 

 


4. Liste des astuces et commandes à savoir

4.1. Mettre à jour un fichier de conf NSClient++ (Windows)

4.1.1. Choses à savoir

Dans les dernières versions du plugin, l'arborescence est la suivante :

9  C:
9  BT-NSCP32
9  local
9  scripts
Le script sbire.pl est dans le répertoire scripts, et tout exécution de commande (ou téléchargement de fichier) se fera relativement à ce répertoire.

Les fichiers commun.ini et specif.ini (configuration locale des plugins) sont dans le répertoire local.

Le fichier nsclient.ini (configuration globale de nsclient++) est situé dans le répertoire BT-NSCP32.

 

Sous Windows, il est impossible à un process de couper le service qui l’a lancé. Il est donc techniquement impossible pour sbire de relancer NSClient++ (à la manière du client Linux qui peut relancer le service NRPE).

L’agent pour Windows contient donc un service nommé ‘restart-nscp’ dont le rôle est de relancer le service ‘BT-NSClient++’. Une commande NRPE ‘restart’ a d’ailleurs été définie dans ce but.


4.1.2. En résumé :

ATTENTION : ces informations semblent erronées. Selon les serveurs, la base serait C:\BT-NSCP32. A vérifier.

Fichier

Emplacement

Chemin relatif

sbire.pl

C:\BT-NSCP32\local\scripts

.

Tous les plugins

C:\BT-NSCP32\local\scripts

.

commun.ini

C:\BT-NSCP32\local

..

specif.ini

C:\BT-NSCP32\local

..

nsclient.ini

C:\BT-NSCP32

..\..

 

Note : comment utiliser .. et le caractère \ avec un client sous Windows ?

- Il faut avoir la version de sbire 0.9.13 (et sbire_master en 0.9.4) minimum. En effet, \  fait partie de la liste des caractères interdits par NRPE, et il n'est donc pas possible de définir un chemin relatif avant cette version (qui implémente un contournement).

- Par ailleurs, le passage de paramêtre entre le shell Unix et le script perl (sb_sergent) oblige d'utiliser \\\\ (4 anti-slash) au lieu d'un seul, d'où les syntaxes ci-dessous.


4.1.3. Exemple :

Download, edition, puis upload de la configuration globale de NSClient++.

# ./sb_sergeant.pl HPLAVIL04 -c download -n ..\\\\..\\\\nsclient.ini > tmp/nsclient.ini

# dos2unix tmp/nsclient.ini

# dos2unix tmp/nsclient.ini

# vi tmp/nsclient.ini

(...)

# unix2dos tmp/nsclient.ini

# ./sb_sergeant.pl HPLAVIL04 -c upload -n ..\\\\..\\\\nsclient.ini -f tmp/nsclient.ini

Le service NSClient++ doit alors être relancé, et ceci se fait directement à partir de la commande NRPE 'reload' :

# /usr/local/nagios/libexec/check_nrpe -H 194.2.53.44 -n -p 3180 -c reload

The restart-nsc service is starting.

The restart-nsc service was started successfully.

[root@poller-btvlb-03 sbire-master]# /usr/local/nagios/libexec/check_nrpe -H 194.2.53.44 -n -p 3180

I (0,4,1,89 2013-01-21) seem to be doing fine...

 


4.2. Mettre sbire.pl à jour

Il est conseillé de commencer par vérifier le numéro de version distant de sbire, et surtout à quel endroit il est situé sur le serveur distant, avec la commande –c info.

Sur un serveur Windows, le chemin relatif est local/scripts :

[root@POLLER sbire-master]# ./sb_sergeant.pl DUDAD001 --csv -c info -n sbire.pl

DUDAD001        sbire.pl does not exist in the plugin folder (C:/BT-NSCP32)

[root@POLLER sbire-master]# ./sb_sergeant.pl DUDAD001 --csv -c info -n local/scripts/sbire.pl

DUDAD001        local/scripts/sbire.pl  13741 bytes     Version 0.9.15  Signature : 34fbb59bdc9bfbc9d616818eabeb8793

Sur un serveur Unix, le chemin relatif est libexec :

[root@POLLER sbire-master]# ./sb_sergeant.pl SERVEUR --csv -c info -n libexec/sbire.pl

SERVEUR libexec/sbire.pl        12833 bytes     Version 0.9.12  Signature : 76e04e910e3527221f590328f5a9c8bf

 

Exemple de mise à jour de sbire sur un serveur Unix

# ./sb_sergeant.pl SERVEUR -c upload -n libexec/sbire.pl -f server_side/sbire.pl

---------------------------

| SERVEUR (194.2.53.44) |

---------------------------

.....................OK

 

# [root@POLLER sbire-master]# ./sb_sergeant.pl SERVEUR

---------------------------

| SERVEUR (194.2.53.44) |

---------------------------

Sbire.pl Version 0.9.15  (RSA:no)

(TODO : Il faudra trouver un moyen de définir une variable pour l’emplacement relatif de sbire au BASE_DIR, ce qui permettrait de mettre à jour tous les serveurs en une fois)

 

 


5. Aide mémoire des commandes pratiques pour Sbire :

5.1. Mettre à jour un sbire Windows en version antérieure à 0.9.16

Avant la version 0.9.16, plusieurs bugs rendaient difficile la mise à jour de sbire.

[root@POLLER-ASIPMSS-01 sbire-master]# ./sb_sergeant.pl Acronis-ASN

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

Sbire.pl Version 0.9.11  (RSA:no)

 

[root@POLLER-ASIPMSS-01 sbire-master]# ./sb_sergeant.pl Acronis-ASN -c run -- cd

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

C:\BT-NSCP64

 

 

[root@POLLER-ASIPMSS-01 sbire-master]# vi placeholder.txt (Créer un fichier contenant au moins 1 caractère)

 

[root@POLLER-ASIPMSS-01 sbire-master]# ./sb_sergeant.pl Acronis-ASN -c config -- USE_RSA 0

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

OK

 

 

[root@POLLER-ASIPMSS-01 sbire-master]# ./sb_sergeant.pl Acronis-ASN -c upload -n local/placeholder.txt -f placeholder.txt

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

.OK

 

(Ces commandes créent les répertoires intermédiaires %ARCHIVE%/BT-NSCP64 et %ARCHIVE%/BT-NSCP64/local avant de pouvoir créer %ARCHIVE%/BT-NSCP64/local/scripts

 

 

 

[root@POLLER-ASIPMSS-01 sbire-master]# ./sb_sergeant.pl Acronis-ASN -c upload -n local/scripts/sbire.pl -f server_side/sbire.pl

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

.......................OK

 

[root@POLLER-ASIPMSS-01 sbire-master]# ./sb_sergeant.pl Acronis-ASN

-----------------------------

| Acronis-ASN (10.0.16.251) |

-----------------------------

sbire.pl Version 0.9.16  (RSA:no)

 

 


Install

Remote NRPE server install

Au préalable vous avez installé correctement l'agent NRPE sur le serveur distant à superviser . Vérifiez à l'aide la commande  check_nrpe -H <IP> , cela vous retournera la version de NRPE utilisé

sbire.pl doit etre copié sur le serveur à superviser . Vous devriez le placer dans le répertoire  contenant les plugins de supervisions. (Dans notre exemple /usr/local/nagios/libexec/.)

Editez nrpe.cfg et rajoutez les lignes suivantes (adaptez les path à vos install ) :

command[sbire]=/opt/nagios/libexec/sbire.pl /opt/nagios/etc/sbire.conf $ARG1$ $ARG2$ $ARG3$ $ARG4$ $ARG5$ 2>&1
Il est conseillé par la suite de séparer les commandes dans un fichier à part :

include=/opt/nagios/libexec/nrpe-command.cfg
Cela permettra de ne modifier que cette partie pour ajouter/effacer/modifier les plugins. 

Creer le fichier de configuration sbire.conf 

 /opt/nagios/etc/sbire.conf 

SESSIONDIR = /opt/nagios/tmp/sbire
ARCHIVEDIR = /opt/nagios/tmp/sbire/archive
BASEDIR = /opt/nagios
PUBLIC_KEY = /opt/nagios/etc/sbire_rsa.pub
NRPE_SERVICE_NAME = nrpe
USE_RSA_DC_BASED_IMPLEMENTATION=1
USE_RSA = 0
ALLOW_UNSECURE_UPLOAD = 1
CONFIG_LOCKED = 0
(...)
(If the remote server is Linux) : Type the following line :

echo "nagios ALL = NOPASSWD: which service" >>/etc/sudoers
which will allow the nagios user to restart the NRPE service (which will be very helpful)

Restart the NRPE server.

sudo service nrpe restart
Usage

To check if configuration is correct, run :

./sbire_master.pl -H $HOSTADDRESS$ 
It should return  :

sbire.pl Version 0.9.15
To transfert or update a NRPE plugin, write :

./sbire_master.pl -H -c update -n -f
Where : is the name of the NRPE script (in the remote folder) is the filename of the script to transfert

This will do the following :

If and are identical, nothing is done (an MD5 comparison is performed)
is sent to the NRPE server in a temporary folder (SESSION_FOLDER)
If a file already exist, then it's archived
The new file is written/replaced.
