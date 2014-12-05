#!/bin/bash
#############################################
# Script by Zachary Powell (zacthespack)    #
# Fixes to allow running as a non-root user #
# by Barry flanagan <barry@flanagan.ie>     #
#############################################

export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin
export TERM=linux
export HOME=/root

################################
# Find and read config file    #
# or use defaults if not found #
################################
run_ssh=ask
run_vnc=ask
resolution=ask

cfgfile=/root/cfg/linux.config # Default config file if not specified

if [ -f /root/cfg/.running_config ]; then
	source /root/cfg/.running_config
fi

if [ $# -ne 0 ]; then
	cfgfile=/root/cfg/$1.config
	if [ -f $cfgfile ]; then
		echo "Using config file $cfgfile"
	else
		echo "Config file not found, using defaults!($cfgfile)"
	fi
fi

if [ -f $cfgfile ]; then
	source $cfgfile
	echo "cfgfile=$cfgfile" > /root/cfg/.running_config   # To make it possible to chroot into a mounted image from the app
	echo "Config file loaded"
else
	if [ -f /root/cfg/.running_config ]; then
		rm /root/cfg/.running_config
	fi
fi

#############################################
# Fixes for first boot including setting up #
# User                                      #
#############################################
if [ ! -f /root/DONOTDELETE.txt ]
	then
	echo "Starting first boot setup......."
	chmod a+rw  /dev/null 
	chmod a+rw  /dev/ptmx
	chmod 1777 /tmp
	chmod 1777 /dev/shm
	chmod +s /usr/bin/sudo
	groupadd -g 3001 android_bt 
	groupadd -g 3002 android_bt-net 
	groupadd -g 3003 android_inet
	groupadd -g 3004 android_net-raw
	mkdir /var/run/dbus
	chown messagebus.messagebus /var/run/dbus
	chmod 755 /var/run/dbus
	usermod -a -G android_bt,android_bt-net,android_inet,android_net-raw messagebus
	echo "shm /dev/shm tmpfs nodev,nosuid,noexec 0 0" >> /etc/fstab
	cd /root
	tar cf - .vnc |(cd /home/ubuntu ; tar xf -)
	chown -R ubuntu.ubuntu /home/ubuntu
	echo
	echo  "Now give your user account (named ubuntu) a password"
	echo
	echo  "Please enter the new password below"
	echo
	passwd ubuntu
	usermod -a -G admin ubuntu
	usermod -a -G android_bt,android_bt-net,android_inet,android_net-raw ubuntu

	# Fix for sdcard read/write permissions by Barry flanagan
	chown ubuntu /external-sd/
	groupadd -g 1015 sdcard-rw
	usermod -a -G sdcard-rw ubuntu

	echo "boot set" >> /root/DONOTDELETE.txt
fi

###########################################
# Tidy up previous LXDE and DBUS sessions #
###########################################
rm /tmp/.X* > /dev/null 2>&1
rm /tmp/.X11-unix/X* > /dev/null 2>&1
rm /root/.vnc/localhost* > /dev/null 2>&1
rm /var/run/dbus/pid > /dev/null 2>&1
rm /var/run/reboot-required* > /dev/null 2>&1

############################################################
# enable workaround for upstart dependent installs         #
# in chroot'd environment. this allows certain packages    #
# that use upstart start/stop to not fail on install.      #
# this means they will have to be launched manually though #
############################################################
dpkg-divert --local --rename --add /sbin/initctl > /dev/null 2>&1
ln -s /bin/true /sbin/initctl > /dev/null 2>&1

###############################################################
# Ask if ssh and vnc should start if the setting don't exists #
###############################################################
if [ $run_vnc == ask ]; then
	echo "Start VNC server? (y/n)"
	read answer
	if [ $answer == y ]; then
		run_vnc=yes
	else
		run_vnc=no
	fi
fi

if [ $run_ssh == ask ]; then
	echo "Start SSH server? (y/n)"
	read answer
	if [ $answer == y ]; then
		run_ssh=yes
	else
		run_ssh=no
	fi
fi

#################################################
# If VNC server should start we do it here with #
# given resolution and DBUS server              #
#################################################
if [ $run_vnc == yes ]; then
	# Asks User for screen size and saves as $resolution
	if [ $resolution == ask ]; then
		echo "Now enter the screen size you want in pixels (e.g. 800x480), followed by [ENTER]:"
		read resolution
	fi

	su ubuntu -l -c "vncserver :0 -geometry $resolution"
	dbus-daemon --system --fork > /dev/null 2>&1

	echo
	echo "If you see the message 'New 'X' Desktop is localhost:0' then you are ready to VNC into your ubuntu OS.."
	echo
	echo "If connection from a different machine on the same network as the android device use the address below:"
	##########################################
	# Output IP address of android device    #
	##########################################
	ifconfig | grep "inet addr" -B3
	#ifconfig wlan0 | awk '/inet addr/ {split ($2,A,":"); print A[2]}'

	echo
	echo "If using androidVNC, change the 'Color Format' setting to 24-bit colour, and once you've VNC'd in, change the 'input mode' to touchpad (in settings)"
fi

############################################
# If SSH server should start we do it here #
############################################
if [ $run_ssh == yes ]; then
	/etc/init.d/ssh start

	if [ ! $run_vnc == yes ]; then # We only echo the following if VNC server is off, if it's on it already output the ip to the user!
		echo "If connecting from a different machine on the same network as the android device use the address below:"
		ifconfig | awk '/inet addr/ {split ($2,A,":"); print A[2]}'
	fi
fi

########################################################################
# If not the config file exist we ask the user if he want to create it #
########################################################################
if [ ! -f $cfgfile ]; then
	echo "Save settings as defaults? (y/n) (You can always change it later in the app)"
	read answer
	if [ $answer == y ]; then
		echo "Config saved to $cfgfile"
		echo "resolution=$resolution" > $cfgfile
		echo "run_ssh=$run_ssh" >> $cfgfile
		echo "run_vnc=$run_vnc" >> $cfgfile

		echo "cfgfile=$cfgfile" > /root/cfg/.running_config   # To make it possible to chroot into a mounted image from the app
		fi
fi


echo
echo "To shut down the Linux environment, just enter 'exit' at this terminal - and WAIT for all shutdown routines to finish!"
echo

# remount sdcard with different permissions
#echo "Remounting sdcards with proper permissions"
#egrep -v '^(bindfs),' /etc/mtab
#bindfs -o perms=0700,mirror-only=ubuntu /sdcard /mnt/sdcard
#bindfs -o perms=0700,mirror-only=ubuntu /android/sdcard2 /mnt/sdcard2
