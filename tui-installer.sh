#!/bin/sh


#Installer SmioS Gnu/Linux 
#All rights reserved for Team-Smi

VERSION=1.0
: ${DIALOG=dialog}

# Installer actions can be specified on cmdline (install or upgrade).
if [ -n "$1" ]; then
	ACTION=$1
else
	ACTION=install
fi
#les variables utilses
DRIVE_NAME=`cat /proc/sys/dev/cdrom/info | grep "drive name" | cut -f 3`
CDROM=/dev/$DRIVE_NAME
KERNEL=vmlinuz-`uname -r`
TARGET_ROOT=/mnt/target
LOG=/var/log/smi-installer.log
BACKLIST="SmioS GNU/Linux installer"

#message de debut
START_INSTALL_MSG="\n
Bienvenue dans l'installateur de SmioS GNU/Linux. Vous pouvez utiliser \
les flèches du clavier et la touche ENTER ou la souris pour valider. Il vous \
suffira de répondre à quelques questions lors des différentes étapes \
d'installation . \
l'installateur va vous demander la partition à utiliser comme racine du \
système et vous proposer de la formater. Ensuite il va copier les fichiers \
depuis le cdrom, les décompresser, les installer et va préconfigurer le \
système. Pour finir, vous aurez aussi la possibilité d'installer le \
gestionnaire de démarrage GRUB, si besoin est.\n\n
\Z4Commencer une installation de SmioS ?\Zn"
##################################
#les fonctions de l'installateur #
##################################

#affiche un message d'erruers
error_message()
{
	$DIALOG --title " Erreur " \
		--colors --backtitle "$BACKLIST" \
		--clear --msgbox "\n$ERROR_MSG" 18 70
}
#cette fonction verifie la valeur taper oui ou bien non 
#pour decider a continue ou bien arreter 
# la valeur 3 pour la nouvelle button ajouté
check_retval()
{
	case $retval in
		0)
			continue ;;
		1)
			echo -e "\nArrêt volontaire.\n" && exit 0 ;;
		3)
			continue ;;
		255)
			echo -e "ESC presser.\n" && exit 0 ;;
	esac
}

#commence l'installation du SmioS
start_installer()
{
	$DIALOG --title " Installation de SmioS" \
		--backtitle "$BACKLIST" \
		--yes-label "Install" \
		--no-label "Quitter" \
		--clear --colors --yesno "$START_INSTALL_MSG" 18 70
	retval=$?
		case $retval in
		0)
			ACTION=install ;;
		1)
			echo -e "\nArrêt volontaire.\n" && exit 0 ;;
		3)
			ACTION=upgrade ;;
		255)
			echo -e "ESC presser.\n" && exit 0 ;;
	esac
	echo "start_installer: `date`" > $LOG
}

#mounter le cdrom
mount_cdrom()
{
	ERROR_MSG=""
	umount /media/cdrom 2>/dev/null
	(
	echo "XXX" && echo 30
	echo -e "\nCréation du point de montage (/media/cdrom)..."
	echo "XXX"		
	mkdir -p /media/cdrom
	sleep 1
	echo "XXX" && echo 60
	echo -e "\nMontage du cdrom ($CDROM)..."
	echo "XXX"
	if mount -t iso9660 $CDROM /media/cdrom 2>>$LOG ;then
	echo "XXX" && echo 90
	echo -e "\nVérification du media d'installation..."
	echo "XXX"
	elif mount -t iso9660 /dev/hdc /media/cdrom 2>>$LOG ;then
	echo "XXX" && echo 90
	echo -e "\nVérification du media d'installation..."
	echo "XXX"
	else mount -t iso9660 /dev/cdrom /media/cdrom 2>>$LOG 
	echo "XXX" && echo 90
	echo -e "\nVérification du media d'installation..."
	echo "XXX"
	fi
	sleep 2
	) |
	$DIALOG --title " Montage du cdrom " \
		--backtitle "$BACKLIST" \
		--gauge "Préparation du media d'installation..." 18 70 0
	# Exit with error msg if no rootfs.gz found
	if [ ! -f /media/cdrom/boot/rootfs1.tar.gz ]; then
		ERROR_MSG="\
Impossible de trouver : les fichiers compresses rootfs[1-5].tar.gz\n\n
L'archive du système de fichiers racine n'est pas présente sur le cdrom. \
 Arrêt."
		error_message
		echo "missing: /media/cdrom/boot/rootfs[1-5].tar.gz" >>$LOG
		exit 1
	fi
}



#des questions sur les systeme de fichiers disponibles sur votre OS
ask_for_target_dev()
{
	exec 3>&1
	TARGET_DEV=`$DIALOG --title " Partition racine " \
		--backtitle "$BACKLIST" --clear \
		--extra-label "List" --extra-button \
		--colors --inputbox "\n
Veuillez indiquer la partition à utiliser pour installer SmioS GNU/Linux, \
exemple: '/dev/hda1'. Vous pouvez utiliser le bouton \Z4'List' \Zn pour afficher \
une liste des partitions disponibles sur votre OS et revenir \
ensuite à cet écran.\n\n
\Z2Partition à utiliser:\Zn" 18 70 2>&1 1>&3`
	retval=$?
	exec 3>&-
	check_retval
	# Display list and comme back.
	if [ "$retval" = "3" ]; then
		fdisk_list
		ask_for_target_dev
	fi
	# si la valeur encore vide
	if [ -z $TARGET_DEV ]; then
		ask_for_target_dev
	fi
	# verifie si vous etes utilise un partition  n'existe pas dans /proc/partitions.
	DEV_NAME=${TARGET_DEV#/dev/}
	if cat /proc/partitions | grep -q $DEV_NAME; then
		echo "ask_for_target_dev: $TARGET_DEV" >>$LOG
	else
		ERROR_MSG="La partition \Z2$TARGET_DEV\Zn n' existe pas."
		error_message
		ask_for_target_dev
	fi
}


# Affiche les partitions disponibles.
fdisk_list()
{
	LIST_PARTITIONS=`fdisk -l | grep ^/dev | sed s/'e Win95'/'e'/g`
	$DIALOG --title "Table de Partition " \
		--backtitle "$BACKLIST" \
		--clear --msgbox "\n
Liste des partitions disponibles :\n\n
$LIST_PARTITIONS" 18 70
}

#des questions sur les type de systeme de fichier
ask_for_mkfs_target_dev()
{
	$DIALOG --title " Formater " \
		--backtitle "$BACKLIST" \
		--clear --colors --yesno "\n
SmioS va être installé sur la partition : $TARGET_DEV\n\n
Vous avez la possibilité de formater la partition en ext3 . Le format ext3 est \
un système de fichiers propre à Linux,  stable et jounalisé, c'est \
le format conseillé. Faites attention, si vous formatez toutes les données \
de cette partition seront définitivement détruites.\n\n
\Z2Faut t'il formater la partition en ext3 ?\Zn" 18 70
	retval=$?
	case $retval in
		0)
			MKFS_TARGET_DEV="ext3"
			echo "mkfs_target_dev: ext3" >>$LOG ;;
		1)
			echo "mkfs_target_dev: annuler" >>$LOG ;;
		255)
			echo -e "ESC presser.\n" && exit 0 ;;
	esac
	
}


# Mounter and mkfs  progression bare.
prepare_target_dev()
{
	(
	echo "XXX" && echo 30
	echo -e "\nPréparation de la partition cible..."
	echo "XXX"
	
	if mount | grep -q $TARGET_ROOT; then
		umount $TARGET_ROOT 2>$LOG
	fi
	sleep 2
		
	if [ "$MKFS_TARGET_DEV" == "ext3" ]; then
		echo "XXX" && echo 60
		echo -e "\nExécution de mkfs.ext3 sur $TARGET_DEV"
		echo "XXX"		
		mkfs.ext3 $TARGET_DEV >>$LOG 2>>$LOG
	else
		echo "XXX" && echo 60
		echo -e "\nLa partition ($TARGET_DEV) sera nettoyée..."
		echo "XXX"
		sleep 2
	fi
	
	echo "XXX" && echo 90
	echo -e "\nCréation du point de montage: $TARGET_ROOT"
	echo "XXX"	
	mkdir -p $TARGET_ROOT
	sleep 2
	
	) |
	$DIALOG --title " Préparation de la cible " \
		--backtitle "$BACKLIST" \
		--gauge " preparation de formatage..." 18 70 0
	# Mount target
	mount $TARGET_DEV $TARGET_ROOT >>$LOG 2>>$LOG
}

# question pour hostanme apres l'installation du systeme.
ask_for_hostname()
{
	exec 3>&1
	HOSTNAME=`$DIALOG --title " Hostname " \
		--backtitle "$BACKLIST" --clear \
		--colors --inputbox "\n
Veuillez indiquer le nom de machine à utiliser pour votre système SmioS.\
Le nom de machine ou 'hostname' est utilisé pour identifier votre machine sur \
le réseau et en local par le système (defaut: smios).\n\n
\Z2Nom de machine:\Zn" 18 70 "SmioS" 2>&1 1>&3`
	retval=$?
	exec 3>&-
	check_retval
	# si la valeur est vide
	if [ -z $HOSTNAME ]; then
		HOSTNAME="SmioS"
	fi
}

# Installation du systeme de fichier avec une bare de progression
install_files()
{
	(
	
	echo "XXX" && echo 10
	echo -e "\nNettoyage de la partition racine si nécessaire..."
	echo "XXX"
	
	echo "XXX" && echo 20
	echo -e "\nInstallation du noyau ($KERNEL)..."
	echo "XXX"
	
	echo "XXX" && echo 30
	echo -e "\nCopie du système compressé (rootfs[1-3.].tar.gz)..."
	echo "XXX"
	cp /media/cdrom/boot/rootfs1.tar.gz $TARGET_ROOT
	cp /media/cdrom/boot/rootfs2.tar.gz $TARGET_ROOT
	cp /media/cdrom/boot/rootfs3.tar.gz $TARGET_ROOT
	sleep 2
	echo "XXX" && echo 40
	echo -e "\nCopie du système compressé (rootfs[4-5].tar.gz)..."
	echo "XXX"
	cp /media/cdrom/boot/rootfs4.tar.gz $TARGET_ROOT
	cp /media/cdrom/boot/rootfs5.tar.gz $TARGET_ROOT
	sleep 2
	
	echo "XXX" && echo 45
	echo -e "\nExtraction du système racine..."
	echo "XXX"
	extract_rootfs1
	
	echo "XXX" && echo 50
	echo -e "\nExtraction du système racine..."
	echo "XXX"
	extract_rootfs2
	
	echo "XXX" && echo 55
	echo -e "\nExtraction du système racine..."
	echo "XXX"
	extract_rootfs3
	
	echo "XXX" && echo 60
	echo -e "\nExtraction du système racine..."
	echo "XXX"
	extract_rootfs4
	
	echo "XXX" && echo 65
	echo -e "\nExtraction du système racine..."
	echo "XXX"
	extract_rootfs5

	echo "XXX" && echo 70
	echo -e "\nPreconfiguration du système..."
	echo "XXX"
	pre_config_system
	
	echo "XXX" && echo 90
	echo -e "\nCréation du fichier de configuration de GRUB (grub.cfg)..."
	echo "XXX"
	grub_config
	
	echo "XXX" && echo 100
	echo -e "\nFin de l'installation des fichiers..."
	echo "XXX"
	echo "install_files: OK" >>$LOG
	sleep 4
	
	) |
	$DIALOG --title " Installation des fichiers " \
		--backtitle "$BACKLIST" \
		--gauge "Installation du systeme de base..." 18 70 0
}


#extraction la partie 1 du fichier compresse
	extract_rootfs1()
{
	cd $TARGET_ROOT
	tar xf rootfs1.tar.gz 2>>$LOG
	rm -f rootfs1.tar.gz
}
#extraction la partie 2 du fichier compresse
	extract_rootfs2()
{
	cd $TARGET_ROOT
	tar xf rootfs2.tar.gz 2>>$LOG
	rm -f rootfs2.tar.gz
}
#extraction la partie 3 du fichier compresse
	extract_rootfs3()
{
	cd $TARGET_ROOT
	tar xf rootfs3.tar.gz 2>>$LOG
	rm -f rootfs3.tar.gz
}
#extraction la partie 4 du fichier compresse
	extract_rootfs4()
{
	cd $TARGET_ROOT
	tar xf rootfs4.tar.gz 2>>$LOG
	rm -f rootfs4.tar.gz
}
#extraction la partie 5 du fichier compresse
	extract_rootfs5()
{
	cd $TARGET_ROOT
	tar xf rootfs5.tar.gz 2>>$LOG
	rm -f rootfs5.tar.gz
}

# Pre configure freshly installed system (70 - 90%).
pre_config_system()
{
	cd $TARGET_ROOT

	echo "XXX" && echo 75
	echo -e "\nAjout de $TARGET_DEV à CHECK_FS du fichier /etc/rcS.conf..."
	echo "XXX"
	sed -i s#'CHECK_FS=\"\"'#"CHECK_FS=\"$TARGET_DEV\""# etc/rcS.conf
	sleep 2
	# Set hostname.
	echo "XXX" && echo 80
	echo -e "\nConfiguration du nom de machine: $HOSTNAME"
	echo "XXX"
	echo $HOSTNAME > etc/hostname
	sleep 2
	echo "$TARGET_DEV      / ext3 defaults       0       0">> /etc/fstab 
		
}


#  GRUB determine les numeros de partitions.
grub_config()
{
		#s=/dev/sda2 ===>a2
	DISK_LETTER=${TARGET_DEV#/dev/[h-s]d}
	#========>2
	DISK_LETTER=${DISK_LETTER%[0-9]}
	#si la partition=/dev/sda2 ====>1
	GRUB_PARTITION=$((${TARGET_DEV#/dev/[h-s]d[a-z]}-1))
	for disk in a b c d e f g h
	do
		nb=$(($nb+1))
		if [ "$disk" = "$DISK_LETTER" ]; then
			GRUB_DISK=$(($nb-1))
			break
		fi
	done
	GRUB_ROOT="(hd${GRUB_DISK},${GRUB_PARTITION})"
	# Creat the target GRUB configuration.
	mkdir -p $TARGET_ROOT/boot/grub
	cat > $TARGET_ROOT/boot/grub/grub.cfg << EOF
# /boot/grub/menu.lst: GRUB boot loader configuration.
#

# By default, boot the first entry.
default 0

# Boot automatically after 8 secs.
timeout 8

# Change the colors.
color yellow/brown light-green/black

# For booting SmioS from : $TARGET_DEV
		menuentry "SmioS" {
	insmod ext2
	set root='$GRUB_ROOT'
	linux /boot/vmlinuz-3.8.1-smi root=$TARGET_DEV
}

EOF
	# log
	echo "grub_config: $TARGET_ROOT/boot/grub/grub.cfg" >>$LOG
	sleep 2
}

grub_install()
{
	TARGET_DISK=`echo $TARGET_DEV | sed s/"[0-9]"/''/`
	$DIALOG --title " GRUB install " \
		--backtitle "$BACKLIST" \
		--clear --colors --yesno "\n
Avant de redémarrer sur votre nouveau système SmioS GNU/Linux, veuillez \
vous assurer qu'un gestionnaire de démarrage est bien installé. Si ce n'est \
pas le cas vous pouvez répondre oui et installer GRUB. Si vous n'installez \
pas GRUB, un fichier de configuration (grub.cfg) a été généré pendant \
l'installation, il contient les lignes qui permettent de démarrer SmioS.\n\n
Une fois installé, GRUB peut facilement être reconfiguré et propose un SHell \
interactif au boot.\n\n
\Z2Faut t'il installer GRUB sur: $TARGET_DISK ?\Zn" 18 70
	retval=$?
	case $retval in
		0)
			(
			echo "XXX" && echo 50
			echo -e "\nExécution de grub-install sur : $TARGET_DISK..."
			echo "XXX"		
			grub-install --no-floppy \
				--root-directory=$TARGET_ROOT $TARGET_DISK 2>>$LOG
			echo "XXX" && echo 100
			echo -e "\nFin de l'installation..."
			echo "XXX"
			sleep 2
			) |
			$DIALOG --title " installation de Grub " \
				--backtitle "$BACKLIST" \
				--gauge "Installation de GRUB..." 18 70 0 ;;
		1)
			echo "grub_install: NO" >>$LOG ;;
		255)
			echo -e "ESC presser.\n" && exit 0 ;;
	esac
}

#fin installation du SmioS
end_of_install()
{
	echo "end_of_install: `date`" >>$LOG
	$DIALOG --title " Installation terminée " \
		--backtitle "$BACKLIST" \
		--yes-label "Exit" \
		--no-label "Reboot" \
		--clear --colors --yesno "\n
L'installation est terminée. Vous pouvez de maintenant redémarrer (reboot) \
sur votre nouveau système SmioS GNU/Linux et commencer  le \
sous serons tres heureux de votre consultation sur notre \
site  www.smios.org
." 18 70
	retval=$?
	case $retval in
	0)
		TITLE="Exiting"
		umount_devices ;;
	1)
		TITLE="Rebooting"
		umount_devices
		reboot || reboot -f ;;
	255)
		echo -e "ESC presser.\n" && exit 0 ;;
esac
}




start_installer
case $ACTION in
	install|*)
		mount_cdrom
		ask_for_target_dev
		ask_for_mkfs_target_dev
		prepare_target_dev
		ask_for_hostname
		install_files
		grub_install
		end_of_install
		;;
		255) echo "vous choisir d'installer pas SmioS"
esac
