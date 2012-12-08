#!/bin/sh

##
#  BuBU <bubu@openaos.org>
##

VERBOSE=0

# Enable Compcache
ENABLE_COMPCACHE=1

if [ $PRODUCT_GEN -eq 7 ]; then
	ENABLE_COMPCACHE=0
fi

# enable unionfs (for rooted device)
ENABLE_UNIONFS=0
CLEAR_UNIONFS=0
# define initramfs version in function readOpenAOSFeatures()
INITRAMFS_VERSION=""
COPY_ARCHOS_FILES_AGAIN=0


#Usage FBMenu --> "Usage: fbmenu title subtitle default timeout reversed_ts reverse_screen opt1 opt2..."

BOOT_IMAGE=
MENUFILE_PATH=/menu.lst
#reverse_ts
ROTATE_TS=0
#reverse_screen
ROTATE_LCD=0
TIME_OUT_MENU=20

ARCHOSSQFS_DIR="/mnt/archos-sqfs"

# archos specific
AOSPARSER=/bin/aosparser
CRAMFSCHECKER=/bin/cramfschecker
FB_WRITE=/bin/fb_write
FLASH_PARTITION_ERASE=/bin/flash_partition_erase
GET_INFO=/bin/get_info
GET_STORAGE_PROP=/bin/get_storage_prop
RFBI_REFRESH=/bin/rfbi_refresh
USB_TS_ENABLE=/bin/usb_ts_enable
REBOOT_INTO=/bin/reboot_into

# busybox
CAT=/bin/cat
CHMOD=/bin/chmod
CUT=/bin/cut
GREP=/bin/grep
INSMOD=/sbin/insmod
LOSETUP=/sbin/losetup
MKDIR=/bin/mkdir
MOUNT=/bin/mount
UMOUNT=/bin/umount
RM=/bin/rm
TOUCH=/bin/touch
ZCAT=/bin/zcat
CP=/bin/cp

DO_REVERSED_COPY=

SERIAL_ENABLED=0

NEWROOT_DIR="/new-root"
SYSTEM_DIR="/mnt/system"
RAWFS_DIR="/mnt/rawfs"
STORAGE_DIR="/mnt/storage"
INIT_DIR="/openaos/disabled"
INIT_FILE="/openaos_init.ini"

log()
{
        if [ $VERBOSE -ne 0 ]; then
                echo $* 1>&2
        fi
}

log_and_reboot()
{
        log "reboot."
        log $*
        MENU_ERROR=$(echo $*| sed 's/ /\\ /g')
	writeOpenAOSFeatures

        for mount_entry in `$CAT /proc/mounts | $CUT -d ' ' -f2 | $GREP -v "^/proc$" | $GREP -v "^/$" `
		do
                	$UMOUNT $mount_entry

			if [ $? -ne 0 ]; then
				$UMOUNT $mount_entry
			fi
        	done
        SELECTED=`eval fbmenu "Error\ Message" "Rebooting\ in\ 20\ seconds" 0 $TIME_OUT_MENU $ROTATE_TS $ROTATE_LCD "$MENU_ERROR" "Reboot" "PowerOff"`

	display_banner

	if [ -n "$SELECTED" ]; then
	
		case "$SELECTED" in
			Reboot) 	/sbin/reboot -f
			;;
			PowerOff) 	/sbin/poweroff -f
			;;
			*)		/sbin/reboot -f
			;;
		esac
	fi
        
        while true; do sleep 1; done
}

getProductConfig()
{
	# Get board and product information
	PRODUCT_NAME=$($CAT /proc/cpuinfo | $GREP "Hardware" | $CUT -d ' ' -f 3)
	PRODUCT_REVISION=$($GET_INFO r)
	KERNEL_VERSION=$($CAT /proc/version | $CUT -d ' ' -f 3)
	
	BOOT_IMAGE_BASE="/usr/share/openaos"

	PRODUCT_GEN=9
	# Set env variables gen specific
	ARCHOS_FILENAME="androidmerged.squashfs"
	SECURE_ARCHOS_FILENAME="$ARCHOS_FILENAME.secure"
	SECURE_ARCHOS_FULL_PATH="$SYSTEM_DIR/$SECURE_ARCHOS_FILENAME"
	NON_SECURE_ARCHOS_FULL_PATH="$SYSTEM_DIR/$ARCHOS_FILENAME"

	NEWROOT_DEV="/dev/loop0"
	SYSTEM_DEV="/dev/mmcblk0p2"
	RAWFS_DEV="/dev/mmcblk0p1"
	
	STORAGE_DEV="/dev/mmcblk0p4"
	SYSTEM_DEV="/dev/mmcblk0p2"
	
	STORAGE_MOVE_DIR="/mnt/storage"
	
	echo 2048 > /sys/block/mmcblk0/queue/max_sectors_kb
				
	case "$PRODUCT_NAME" in

		A80S) 	BOOT_IMAGE=$BOOT_IMAGE_BASE-1024x768
		;;
		A80H) 	BOOT_IMAGE=$BOOT_IMAGE_BASE-1024x768
			STORAGE_DEV="/dev/sda1"			# Needs confirmation!
		;;
		A101S)	BOOT_IMAGE=$BOOT_IMAGE_BASE-1280x800
		;;
		A101H)	BOOT_IMAGE=$BOOT_IMAGE_BASE-1280x800
			STORAGE_DEV="/dev/sda1"			# Needs confirmation!
		;;
	esac
}

enable_lcd()
{
	echo 150 > /sys/class/leds/lcd-backlight/brightness
}

setInputNodes()
{
	case "$PRODUCT_NAME" in
		A80S|A80H|A101S|A101H)	
			ln -sf /dev/input/event1 /dev/input/keyvol
			ln -sf /dev/input/event2 /dev/input/keypwr

					if [ $ROTATE_TS -eq 1 -o $ROTATE_LCD -eq 1 ]; then
		                                echo Y >/sys/module/hid_hanvon/parameters/rotate180
                        		fi

					# What's that?
		                        # echo Y >/sys/module/hid_hanvon/parameters/tsp_emulation
		;;
	esac
}

unsetInputNodes()
{
if [ $PRODUCT_GEN -eq 8 ]; then
	for f in keybol keypwr touchscreen
		do
			rm -f /dev/input/$f
		done
fi
}

display_banner()
{
        $ZCAT $BOOT_IMAGE | $FB_WRITE $DO_REVERSED_COPY
        $RFBI_REFRESH
}

prepare_menu_os()
{
        MENUFILE=$STORAGE_DIR$MENUFILE_PATH
	GINGERBREAD_FILE="$STORAGE_DIR/openaos-gingerbread.img"

	FROYO_FILE=
	FROYO_FILENAME=

	if [ -f "$STORAGE_DIR/froyo.img" ]; then
		FROYO_FILENAME="froyo.img"
	elif [ -f "$STORAGE_DIR/openaos-froyo.img" ]; then
		FROYO_FILENAME="froyo.img"
	fi

	if [ "x$FROYO_FILENAME" != "x" ]; then
		FROYO_FILE="$STORAGE_DIR/$FROYO_FILENAME"
	fi

        if [ -f $MENUFILE ]; then
                dos2unix $MENUFILE
        fi
#Create default menu.lst
        if [ ! -f $MENUFILE ]; then 
                if [ -e $SECURE_ARCHOS_FULL_PATH -o -e $NON_SECURE_ARCHOS_FULL_PATH ]; then
			
                        echo "Archos|ARCHOS|ARCHOS|/init|0" >> $MENUFILE
                fi
                if [ "x$FROYO_FILE" != "x" -a -f $FROYO_FILE ]; then
                        echo "Froyo||/$FROYO_FILENAME|/init|0" >> $MENUFILE
		fi

		if [ -f $GINGERBREAD_FILE -o -f "$GINGERBREAD_FILE.gz" ]; then
                        echo "Gingerbread||/openaos-gingerbread.img|/init|0" >> $MENUFILE
		fi
                echo "Angstrom||/rootfs.img|/sbin/init|1" >> $MENUFILE
#Check existing menu.lst
        else
                if [ -e $SECURE_ARCHOS_FULL_PATH -o -e $NON_SECURE_ARCHOS_FULL_PATH ]; then
                        $GREP -q "|ARCHOS|" $MENUFILE >/dev/null 2>&1

                        if [ $? -ne 0 ]; then
                                echo "Archos|ARCHOS|ARCHOS|/init" >> $MENUFILE
                        fi
                else
                        $GREP -q "|ARCHOS|" $MENUFILE >/dev/null 2>&1

                        if [ $? -eq 0 ]; then
                                $GREP -v "|ARCHOS|" $MENUFILE >$MENUFILE.tmp
                                mv -f $MENUFILE.tmp $MENUFILE
                        fi
                fi

		if [ "x$FROYO_FILE" != "x" -a -f $FROYO_FILE ]; then
			$GREP -qi "^Froyo|" $MENUFILE >/dev/null 2>&1

			if [ $? -ne 0 ]; then
                        	echo "Froyo||/$FROYO_FILENAME|/init|0" >> $MENUFILE
			fi
		fi

		if [ -f $GINGERBREAD_FILE -o -f "$GINGERBREAD_FILE.gz" ]; then
			$GREP -qi "^Gingerbread|" $MENUFILE >/dev/null 2>&1

			if [ $? -ne 0 ]; then
                        	echo "Gingerbread||/openaos-gingerbread.img|/init|0" >> $MENUFILE
			fi
		fi
        fi

	sync
}

do_menu_os()
{
        MENUFILE=$STORAGE_DIR$MENUFILE_PATH

        if [ -f $MENUFILE ] ; then

		if [ ! -f /tmp/menu_os.lst ]; then
			$CAT $MENUFILE >/tmp/menu_os.lst

			echo "Advanced Menu|ADVANCED|ADVANCED||0" >> /tmp/menu_os.lst
		fi

		if [ ! -f /tmp/menu_os.titles ]; then
	                $CAT /tmp/menu_os.lst | while read line
				do
                	        	MENU_TITLE=$(echo $line|$CUT -f 1 -d '|')

                        		echo "\"$MENU_TITLE\" " >> /tmp/menu_os.titles
	                	done
		fi

                IMAGE_SELS=$($CAT /tmp/menu_os.titles)

                #echo "8" > /sys/devices/system/display/gfxformat

                SELECTED=$(eval fbmenu "Boot\ menu" "Select\ OS..." 0 $TIME_OUT_MENU $ROTATE_TS $ROTATE_LCD $IMAGE_SELS)

                # NOTE: We are using the item's display name as a key. 
                # User must put unique names in menu.lst!
                if [ -n "$SELECTED" ]; then
                        ROOTFS_DEVICE=$($GREP "^$SELECTED|" /tmp/menu_os.lst|$CUT -f 2 -d '|')
                        ROOTFS_IMAGE=$($GREP "^$SELECTED|" /tmp/menu_os.lst|$CUT -f 3 -d '|')
                        ROOTFS_INIT=$($GREP "^$SELECTED|" /tmp/menu_os.lst|$CUT -f 4 -d '|')
                        ROOTFS_FBMODE=$($GREP "^$SELECTED|" /tmp/menu_os.lst|$CUT -f 5 -d '|')
                        ROOTFS_OPTION=$($GREP "^$SELECTED|" /tmp/menu_os.lst|$CUT -f 6 -d '|')
                        export ROOTFS_OPTION										
                fi
        fi

        echo "ROOTFS_DEVICE is $ROOTFS_DEVICE" >/tmp/menu_os.log
        echo "ROOTFS_IMAGE is $ROOTFS_IMAGE" >>/tmp/menu_os.log
        echo "ROOTFS_INIT is $ROOTFS_INIT" >>/tmp/menu_os.log
        echo "ROOTFS_FBMODE is $ROOTFS_FBMODE" >>/tmp/menu_os.log
        echo "ROOTFS_OPTION is $ROOTFS_OPTION" >>/tmp/menu_os.log

	#display_banner
}

get_status_string()
{
if [ $* -eq 1 ]; then
	STATUS_STRING="Disable"
else
	STATUS_STRING="Enable"
fi
}

do_menu_advanced()
{
	SHOW_MENU_ADVANCED=1

	while [ $SHOW_MENU_ADVANCED -eq 1 ]
		do
			rm -f /tmp/menu_advanced.titles

			echo "Debugging|DEBUG" > /tmp/menu_advanced.lst
			get_status_string $ENABLE_UNIONFS
			echo "$STATUS_STRING Rooted Device|UNIONFS_$ENABLE_UNIONFS" >>/tmp/menu_advanced.lst
			get_status_string $CLEAR_UNIONFS
			echo "$STATUS_STRING Clear Unionfs Dir|CLEAR_UNIONFS_$CLEAR_UNIONFS" >>/tmp/menu_advanced.lst
			if [ $PRODUCT_GEN -eq 8 ]; then
				get_status_string $ENABLE_COMPCACHE
				echo "$STATUS_STRING Compcache|COMPCACHE_$ENABLE_COMPCACHE" >>/tmp/menu_advanced.lst
			fi
			get_status_string $COPY_ARCHOS_FILES_AGAIN
			echo "$STATUS_STRING Copy Archos Files|COPY_ARCHOS_FILES_$COPY_ARCHOS_FILES_AGAIN" >>/tmp/menu_advanced.lst
			echo "Info about kernel|INFO" >> /tmp/menu_advanced.lst
			echo "Set timeout bootmenu|TIMEOUT" >> /tmp/menu_advanced.lst
			echo "Recovery|RECOVERY" >> /tmp/menu_advanced.lst
			echo "Reboot|REBOOT" >> /tmp/menu_advanced.lst
			echo "Back|BACK" >> /tmp/menu_advanced.lst

			$CAT /tmp/menu_advanced.lst | while read line
				do
					MENU_TITLE=$(echo $line|$CUT -f 1 -d '|')

					echo "\"$MENU_TITLE\" " >> /tmp/menu_advanced.titles
				done

			MENU_SELS=$($CAT /tmp/menu_advanced.titles)

			SELECTED=$(eval fbmenu "Advanced\ Menu" "Select\ Action..." 0 -1 $ROTATE_TS $ROTATE_LCD $MENU_SELS)

			if [ -n "$SELECTED" ]; then
				CHOICE=$($GREP "$SELECTED" /tmp/menu_advanced.lst|$CUT -f 2 -d '|')

				case "$CHOICE" in
					RECOVERY) 	$MOUNT $RAWFS_DEV $RAWFS_DIR -t rawfs || log_and_reboot "mount rawfs fail"
							$REBOOT_INTO -s recovery
							$UMOUNT $RAWFS_DIR

							log_and_reboot "Rebooting to Recovery"
					;;

					REBOOT) 	log_and_reboot "Rebooting"
					;;

					UNIONFS_1)	ENABLE_UNIONFS=0
					;;

					UNIONFS_0)	ENABLE_UNIONFS=1
					;;
					
					CLEAR_UNIONFS_1)	CLEAR_UNIONFS=0
					;;
					
					CLEAR_UNIONFS_0)	CLEAR_UNIONFS=1
					;;

					COMPCACHE_1)	ENABLE_COMPCACHE=0
					;;

					COMPCACHE_0)	ENABLE_COMPCACHE=1
					;;

					COPY_ARCHOS_FILES_1)	COPY_ARCHOS_FILES_AGAIN=0
					;;
					
					COPY_ARCHOS_FILES_0)	COPY_ARCHOS_FILES_AGAIN=1
					;;

					DEBUG)			do_serial_menu
								SHOW_MENU_ADVANCED=0
					;;
					TIMEOUT)		do_timeout_menu
								SHOW_MENU_ADVANCED=0
					;;
					INFO)			do_info_menu
								SHOW_MENU_ADVANCED=0
					;;

					BACK)			SHOW_MENU_ADVANCED=0
					;;
				esac

				echo "CHOICE is $CHOICE" >/tmp/menu_advanced.log
			fi
		done

	# Write the init file
	writeOpenAOSFeatures
}

do_info_menu()
{
	KERNEL_VS=$(uname -v| sed 's/ /\\ /g')
	
	SELECTED=`eval fbmenu "Info\ menu" "Show\ information\ about\ kernel " 0 $TIME_OUT_MENU $ROTATE_TS $ROTATE_LCD "Kernel\ version\ =\ $KERNEL_VS" "$KERNEL_VERSION" "Initramfs\ version\ =\ $INITRAMFS_VERSION" "Back\ to\ advanced\ menu" "Back\ to\ main\ menu"`

	
	if [ "x$SELECTED" = "xBack to advanced menu" ]; then
		do_menu_advanced
	
	fi
}

do_timeout_menu()
{

	SELECTED=`eval fbmenu "Info\ menu" "Show\ information\ about\ kernel " 0 $TIME_OUT_MENU $ROTATE_TS $ROTATE_LCD "1\ sec" "5\ sec" "10\ sec" "15\ sec" "20\ sec" "30\ sec" "Back\ to\ advanced\ menu" "Back\ to\ main\ menu"`
	if [ "x$SELECTED" = "xBack to advanced menu" ]; then
		do_menu_advanced
	elif [ "x$SELECTED" = "xBack to main menu" ]; then
		log "dummy"
	else
		TIME_OUT_MENU=$(echo "$SELECTED" | sed 's/ sec//g')
	fi
	
}

do_img_menu()
{
	rm -f /tmp/menu_img.titles

	ls -1 $STORAGE_DIR/*.img | while read line
		do
			MENU_TITLE=$(basename $line)

			echo "\"/$MENU_TITLE\" " >> /tmp/menu_img.titles
		done

	ls -1 $STORAGE_DIR/*.img.gz | while read line
		do
			MENU_TITLE=$(basename $line)

			echo "\"/$MENU_TITLE\" " >> /tmp/menu_img.titles
		done

	if [ -f /tmp/menu_img.titles ]; then
		MENU_SELS=$($CAT /tmp/menu_img.titles)

		SELECTED=$(eval fbmenu "OS\ Image\ Menu" "Select\ Image..." 0 -1 $ROTATE_TS $ROTATE_LCD $MENU_SELS)

		if [ -n "$SELECTED" ]; then
			ROOTFS_IMAGE=$(echo $SELECTED|$CUT -f 2 -d '"')
			CHECK_GZ=$(echo $ROOTFS_IMAGE|$CUT -d "." -f 1,2)

			if [ "$ROOTFS_IMAGE" = "$CHECK_GZ.gz" ]; then
			    ROOTFS_IMAGE=$CHECK_GZ
			    if [ -f "$ROOTFSIMAGESOURCE_MOUNTPOINT$ROOTFS_IMAGE" ]; then
				mv $ROOTFSIMAGESOURCE_MOUNTPOINT$ROOTFS_IMAGE $ROOTFSIMAGESOURCE_MOUNTPOINT$ROOTFS_IMAGE.bak
			    fi

			    gunzip -d $ROOTFSIMAGESOURCE_MOUNTPOINT$ROOTFS_IMAGE.gz
			
			fi

			echo "ROOTFS_IMAGE is $ROOTFS_IMAGE" >/tmp/menu_img.log
		fi
	else
		echo "Back" >/tmp/menu_bad_img.titles

		MENU_SELS=$($CAT /tmp/menu_bad_img.titles)

		SELECTED=$(eval fbmenu "OS\ Image" "Not\ Found..." 0 -1 $ROTATE_TS $ROTATE_LCD $MENU_SELS)
	fi

	display_banner
}

do_menu()
{
	prepare_menu_os

	SHOW_MENU_OS=1

	while [ $SHOW_MENU_OS -eq 1 ]
		do
			do_menu_os

			case "$ROOTFS_DEVICE" in
				ADVANCED)	do_menu_advanced
						;;

				ARCHOS)		display_banner

						ROOTFS_INIT=/init

						UMOUNT_STORAGE=1

						mountArchosSquashfs 1

						if [ $ENABLE_UNIONFS -eq 1 ]; then
							$INSMOD /lib/modules/$KERNEL_VERSION/kernel/fs/unionfs/unionfs.ko
							
							OVERLAY_DIR=$SYSTEM_DIR/unionfs
							if [ $CLEAR_UNIONFS -eq 1 ]; then
								$RM -rf $OVERLAY_DIR
							fi

							$MKDIR $OVERLAY_DIR
							$MOUNT -t unionfs -o dirs=$OVERLAY_DIR=rw:$NEWROOT_DIR=ro unionfs $NEWROOT_DIR
																					
							if [ -e /rooted/su ]; then
								$CP /rooted/su $NEWROOT_DIR/system/bin/
								$CHMOD 6755 $NEWROOT_DIR/system/bin/su
								if [ $PRODUCT_GEN -eq 7 ]; then
									$RM -rf /rooted/su
								fi
							fi

							if [ -e /rooted/Superuser.apk ]; then
								$CP /rooted/Superuser.apk $NEWROOT_DIR/system/app/
								if [ $PRODUCT_GEN -eq 7 ]; then
									$RM -rf /rooted/Superuser.apk
								fi
							fi 
						
						fi
						if [ $PRODUCT_GEN -eq 8 ]; then
							$USB_TS_ENABLE --detach
						fi
						
						SHOW_MENU_OS=0
				;;

				*)		display_banner
						if [ "x$ROOTFS_DEVICE" != "x" -a "x$ROOTFS_DEVICE" != "x/dev/sda1" ]; then
							$MOUNT $ROOTFS_DEVICE $NEWROOT_DIR -o rw,noatime,nodiratime || log_and_reboot "Mounting rootfs partition failed 1"

							UMOUNT_STORAGE=1
						else
							ROOTFSIMAGESOURCE_MOUNTPOINT=$STORAGE_DIR

							if [ -f "$ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE.gz" ]; then
								if [ -f "$ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE" ]; then
									mv $ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE $ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE.bak
								fi

								gunzip -d $ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE.gz
							fi

							ROOTFS_IMG_IS_BAD=0

							if [ ! -f "$ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE" ]; then
								OLD_ROOTFS_IMAGE=$ROOTFS_IMAGE

								do_img_menu

								if [ ! -f "$ROOTFSIMAGESOURCE_MOUNTPOINT/$ROOTFS_IMAGE" ]; then
									continue
								fi

								ROOTFS_IMG_IS_BAD=1
							fi

							$LOSETUP $NEWROOT_DEV $STORAGE_DIR/$ROOTFS_IMAGE || log_and_reboot "Mounting rootfs partition failed 2"
							$MOUNT $NEWROOT_DEV $NEWROOT_DIR -o rw,noatime,nodiratime || log_and_reboot "Mounting rootfs partition failed 3"

							if [ $ROOTFS_IMG_IS_BAD -eq 1 ]; then
								if [ ! -f $NEWROOT_DIR/$ROOTFS_INIT -a ! -L $NEWROOT_DIR/$ROOTFS_INIT ]; then
									if [ -f $NEWROOT_DIR/init -o -L $NEWROOT_DIR/init ]; then
										ROOTFS_INIT=/init
									elif [ -f $NEWROOT_DIR/sbin/init -o -L $NEWROOT_DIR/sbin/init ]; then
										ROOTFS_INIT=/sbin/init
									elif [ -f $NEWROOT_DIR/bin/init -o -L $NEWROOT_DIR/bin/init ]; then
										ROOTFS_INIT=/bin/init
									fi
								fi

								$CAT $STORAGE_DIR/$MENUFILE_PATH >/tmp/menu.lst.$$

								if [ ! -f $STORAGE_DIR/$MENUFILE_PATH.bad ]; then
									mv -f $STORAGE_DIR/$MENUFILE_PATH $STORAGE_DIR/$MENUFILE_PATH.bad
								else
									rm -f $STORAGE_DIR/$MENUFILE_PATH
								fi

								$CAT /tmp/menu.lst.$$ | while read line
									do
										TMP_NAME=$(echo $line | $CUT -f 1 -d '|')
										TMP_DEVICE=$(echo $line | $CUT -f 2 -d '|')
										TMP_IMAGE=$(echo $line | $CUT -f 3 -d '|')
										TMP_INIT=$(echo $line | $CUT -f 4 -d '|')
										TMP_FBMODE=$(echo $line | $CUT -f 5 -d '|')
										
										if [ "x$TMP_IMAGE" = "x$OLD_ROOTFS_IMAGE" ]; then
											TMP_IMAGE=$ROOTFS_IMAGE
											TMP_INIT=$ROOTFS_INIT
										fi

										echo "$TMP_NAME|$TMP_DEVICE|$TMP_IMAGE|$TMP_INIT|$TMP_FBMODE" >>$STORAGE_DIR/$MENUFILE_PATH
									done

								sync
							fi
						fi

						copyArchosFiles "$NEWROOT_DIR/archos.inc" "$NEWROOT_DIR"

						$UMOUNT $SYSTEM_DIR

						mkdir -p $NEWROOT_DIR$STORAGE_MOVE_DIR
						
						if [ $PRODUCT_GEN -eq 8 ]; then
							if [ $ROTATE_TS -eq 1 -o $ROTATE_LCD -eq 1 ]; then
								echo Y >/sys/module/hid_hanvon/parameters/rotate180
								echo Y >/sys/module/mma7660fc/parameters/rotate180
							fi

							echo Y >/sys/module/hid_hanvon/parameters/tsp_emulation
						else 
							if [ $ROOTFS_FBMODE -eq 1 ]; then
								dd if=/dev/zero of=/dev/fb0 bs=2048
								/sbin/fbset -nonstd 0 -depth 24
							fi
							if [ $NAND_EXISTS -eq 1 ] ; then
								$UMOUNT $SYSTEM_NAND_DIR || log_and_reboot "umount SYSTEM_NAND_DIR failed"
							fi
						fi

						if [ $UMOUNT_STORAGE -eq 0 ]; then
							$MOUNT --move $STORAGE_DIR $NEWROOT_DIR$STORAGE_MOVE_DIR
						fi

						SHOW_MENU_OS=0
				;; # OTHERS
			esac
		done
}

kill_cmd()
{
        for p in $(pidof $*)
                do
                        if [ "x$p" != "x$$" ]; then
                                kill -9 $p
                        fi
                done
}

run_serial_shell()
{
        /bin/sh </dev/$1 >/dev/$1 &
}

kill_serial_shell()
{
        kill_cmd sh
}

kernel_debug_on_serial()
{
        $CAT /proc/kmsg >/dev/$1 &
}

reset_all_tty()
{
   for t in ttyGS0 ttyGS1 ttyGS2 ttyS2
      do
         stty -F /dev/$t echo
      done
}

releaseSerial()
{
	if [ $SERIAL_ENABLED -eq 1 ]; then
		kill_serial_shell
		reset_all_tty
	fi
}

load_musb()
{
	MUSB_EXISTS=$($CAT /proc/modules|$GREP musb)

	if [ "x$MUSB_EXISTS" = "x" ]; then
	        $INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/musb/musb_hdrc.ko mode_default=2 use_dma=1
	fi
}

unload_musb()
{
	rmmod musb_hdrc
}

install_g_ether()
{
	ETHER_EXISTS=$($CAT /proc/modules|$GREP g_ether)

	if [ "x$ETHER_EXISTS" = "x" ]; then
	        $INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/g_ether.ko

		ifconfig usb0 192.168.254.1 netmask 255.255.255.0

		/sbin/udhcpd
	fi
}

install_g_serial()
{
	SERIAL_EXISTS=$($CAT /proc/modules|$GREP g_serial)

	if [ "x$SERIAL_EXISTS" = "x" ]; then
	        $INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/g_serial.ko n_ports=3

		for i in 0 1 2
			do
				if [ -e /sys/class/tty/ttyGS$i/dev ]; then
					rm -f /dev/ttyGS$i
					mknod /dev/ttyGS$i c $($CAT /sys/class/tty/ttyGS$i/dev| sed -r "s/:/ /g")
				fi
			done

		kernel_debug_on_serial ttyGS2

                run_serial_shell ttyGS1
        fi
}

install_g_cdc()
{
	CDC_EXISTS=$($CAT /proc/modules|$GREP g_cdc)

	if [ "x$CDC_EXISTS" = "x" ]; then
		$INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/gadget/g_cdc.ko

		rm -f /dev/ttyGS0
		mknod /dev/ttyGS0 c $($CAT /sys/class/tty/ttyGS0/dev| sed -r "s/:/ /g")

		ifconfig usb0 192.168.254.1 netmask 255.255.255.0

		/sbin/udhcpd 

                run_serial_shell ttyGS0

	        kernel_debug_on_serial ttyGS0
        fi
}

enable_serial()
{
	TYPE=$1

	for f in g_serial g_cdc g_ether
		do
			if [ $f != $TYPE ]; then
				case $f in
					g_serial)	kill_cmd $CAT
							kill_serial_shell
					;;

					g_cdc)		kill_cmd $CAT
							kill_serial_shell
							kill_cmd udhcpd
							ifconfig usb0 down
					;;

					g_ether)	kill_cmd udhcpd
							ifconfig usb0 down
					;;
				esac

				rmmod $f
			fi
		done

	case "$TYPE" in
		g_serial)	install_g_serial
		;;

		g_cdc)		install_g_cdc
		;;

		g_ether)	install_g_ether
		;;
	esac
}

do_serial_menu()
{
	SELECTED=`eval fbmenu "Debugging" "Activate\ Debug" 0 10 $ROTATE_TS $ROTATE_LCD "NONE" "SERIAL" "ETHER" "BOTH"`

	display_banner

	if [ "x$SELECTED" = "xSERIAL" ]; then
		load_musb
		enable_serial g_serial
		SERIAL_ENABLED=1
	elif [ "x$SELECTED" = "xBOTH" ]; then
		load_musb
		enable_serial g_cdc
		SERIAL_ENABLED=1
	elif [ "x$SELECTED" = "xETHER" ]; then
		load_musb
		enable_serial g_ether
		SERIAL_ENABLED=0
	else
		enable_serial none
		unload_musb
		SERIAL_ENABLED=0
	fi
}

mountArchosSquashfs()
{
	is_archos=$1

	if [ $is_archos -eq 0 ]; then
		mkdir -p $ARCHOSSQFS_DIR
		ARCHOSSQFS_ROOTFS_DEV=/dev/loop1
	else
		ARCHOSSQFS_ROOTFS_DEV=/dev/loop0
	fi

	ARCHOS_FULL_PATH=$SECURE_ARCHOS_FULL_PATH

	ARCHOS_CHECK=0

	if [ -f $ARCHOS_FULL_PATH ]; then
		ARCHOS_CHECK=1
	else
		ARCHOS_FULL_PATH="$SYSTEM_DIR/$ARCHOS_FILENAME"
		ARCHOS_CHECK=0
	fi

	if [ $ARCHOS_CHECK -eq 1 ] ; then
		$LOSETUP -o 256 $ARCHOSSQFS_ROOTFS_DEV $ARCHOS_FULL_PATH || log_and_die "Mounting rootfs partition failed"
	else
		$LOSETUP $ARCHOSSQFS_ROOTFS_DEV $ARCHOS_FULL_PATH || log_and_die "Mounting squashfs partition failed"
	fi

	if [ $is_archos -eq 1 ]; then
		$MOUNT $ARCHOSSQFS_ROOTFS_DEV $NEWROOT_DIR || log_and_reboot "Mounting rootfs partition failed"
	else
		$MOUNT $ARCHOSSQFS_ROOTFS_DEV $ARCHOSSQFS_DIR || log_and_reboot "Mounting archos-sqfs partition failed"
	fi
}

umountArchosSquashfs()
{
	is_archos=$1

	if [ $is_archos -eq 1 ]; then
		$UMOUNT $NEWROOT_DIR
	else
		$UMOUNT $ARCHOSSQFS_DIR

		if [ $is_archos -eq 0 ]; then
			ARCHOSSQFS_ROOTFS_DEV=/dev/loop1
		else
			ARCHOSSQFS_ROOTFS_DEV=/dev/loop0
		fi

		$LOSETUP -d $ARCHOSSQFS_ROOTFS_DEV
	fi
}

copyArchosFiles()
{
	archos_inc=$1
	root_dir=$2

	if [ $COPY_ARCHOS_FILES_AGAIN -eq 1 -a -f "$archos_inc.bak" -a ! -f "$archos_inc" ]; then
		mv -f "$archos_inc.bak" "$archos_inc"
	fi

	if [ -f "$archos_inc" ]; then
		mountArchosSquashfs 0
		$CAT "$archos_inc" | while read FILE
			do
				TARGET="$root_dir/$(dirname $FILE)"
				SOURCE="$ARCHOSSQFS_DIR"
				if [ "x$(dirname $FILE)" = "x$RAWFS_DIR" ]; then
				    if [ "x$(df | grep rawfs)" = "x" ]; then
					$MOUNT $RAWFS_DEV $RAWFS_DIR -t rawfs || log_and_reboot "rawfs mount failed"
				    fi
				    SOURCE=""
				fi
				mkdir -p "$TARGET"

				cp -af "$SOURCE/$FILE" "$TARGET/"
			done
		if [ "x$(df | grep rawfs)" != "x" ]; then
		    $UMOUNT $RAWFS_DIR  || log_and_reboot "umount rawfs failed"
		fi
		umountArchosSquashfs 0

		mv -f $archos_inc $archos_inc.bak

		sync
	fi
}

wait_for_storage()
{
	counter=30

	if [ $PRODUCT_NAME = "A80H" -o $PRODUCT_NAME = "A101H" ]; then		# Needs confirmation
		blkdev=/sys/block/sda
	else
		blkdev=/sys/block/mmcblk0
	fi

	while [ $counter -gt 0 -a ! -d $blkdev ]
		do
			sleep 1
			let counter-=1
		done
}

configCompcache()
{
	if [ $ENABLE_COMPCACHE -eq 1 ]; then
		insmod /lib/modules/$KERNEL_VERSION/kernel/mm/xvmalloc.ko
		insmod /lib/modules/$KERNEL_VERSION/kernel/mm/ramzswap_drv.ko disksize_kb=61440
		rzscontrol /dev/ramzswap --init
		echo 60 > /proc/sys/vm/swappiness
		swapon /dev/ramzswap
	fi
}

readOpenAOSFeatures()
{
	if [ -f $STORAGE_DIR$INIT_DIR$INIT_FILE ]; then
		. $STORAGE_DIR$INIT_DIR$INIT_FILE
	fi
# We use the following to change a default setting in previous initramfs.	
	if [ "x$INITRAMFS_VERSION" = "x" ]; then
		ENABLE_UNIONFS=0
	fi
#################################
# Define initramfs version here #
#################################
INITRAMFS_VERSION="1.0.0"
}

writeOpenAOSFeatures()
{
	
	mkdir -p $STORAGE_DIR$INIT_DIR
	echo "INITRAMFS_VERSION=$INITRAMFS_VERSION" > $STORAGE_DIR$INIT_DIR$INIT_FILE	
	echo "ENABLE_UNIONFS=$ENABLE_UNIONFS" >> $STORAGE_DIR$INIT_DIR$INIT_FILE
	echo "ENABLE_COMPCACHE=$ENABLE_COMPCACHE" >> $STORAGE_DIR$INIT_DIR$INIT_FILE
	echo "TIME_OUT_MENU=$TIME_OUT_MENU" >> $STORAGE_DIR$INIT_DIR$INIT_FILE
	sync
}

doOpenAOSUpdate()
{
	if [ -d $STORAGE_DIR/openaos/dump -a -e $SECURE_ARCHOS_FULL_PATH -a ! -e $STORAGE_DIR/openaos/dump/$SECURE_ARCHOS_FILENAME ]; then
		cp $SECURE_ARCHOS_FULL_PATH $STORAGE_DIR/openaos/dump/
	fi
	#FIXME
	if [ $PRODUCT_GEN -eq 7 ]; then
		if [ $NAND_EXISTS -eq 1 ] ; then
			CRAMFS_DIR=$SYSTEM_NAND_DIR
		else 
			CRAMFS_DIR=$SYSTEM_DIR
		fi
		if [ -e $STORAGE_DIR/openaos/update/cramfs/$SECURE_ARCHOS_FILENAME ]; then
			rm -f $CRAMFS_DIR/$SECURE_ARCHOS_FILENAME
			cp $STORAGE_DIR/openaos/update/cramfs/$SECURE_ARCHOS_FILENAME $CRAMFS_DIR
		fi

		if [ -e $STORAGE_DIR/openaos/update/cramfs/$SECURE_BITMAPFS_FILENAME ]; then
			rm -f $CRAMFS_DIR/$SECURE_BITMAPFS_FILENAME
			cp $STORAGE_DIR/openaos/update/cramfs/$SECURE_BITMAPFS_FILENAME $CRAMFS_DIR
		fi
		if [ -d $STORAGE_DIR/openaos/update/system ]; then
			cp -af $STORAGE_DIR/openaos/update/system/* $SYSTEM_DIR/
		fi
		rm -rf $STORAGE_DIR/openaos/update
		
		
	else 
		for f in $STORAGE_DIR/openaos/update/$ARCHOS_FILENAME $STORAGE_DIR/openaos/update/$SECURE_ARCHOS_FILENAME
			do
				if [ -e $f ]; then
					rm -f $SECURE_ARCHOS_FULL_PATH $NON_SECURE_ARCHOS_FULL_PATH
					cp $f $SYSTEM_DIR/
					rm -f $f
					break
				fi
			done
	fi
}

mountStorage()
{
	if [ $PRODUCT_GEN -eq 8 ]; then
		wait_for_storage
	fi
	$MOUNT $STORAGE_DEV $STORAGE_DIR -o rw,fmask=0000,dmask=0000,noatime,nodiratime -t vfat || $MOUNT $STORAGE_DEV $STORAGE_DIR -o rw,fmode=666,dmode=777,noatime,nodiratime || log_and_reboot "mount storage fail"

	UMOUNT_STORAGE=0
}

mountSystem()
{
	# Leaving this here for the HDD-Models
	# TODO: Would it make sense to add the SD-Card and the USB-Host here?
	if [ $PRODUCT_GEN -eq 7 ]; then
		install_mass_storage
		dev_setup
		if [ $NAND_EXISTS -eq 1 ] ; then
			$MOUNT -t ubifs -o rw,noatime $NAND_SYSTEM_DEV $SYSTEM_NAND_DIR || log_and_reboot "mount system nand fail gen7"
			SECURE_ARCHOS_FULL_PATH="$SYSTEM_NAND_DIR/$SECURE_ARCHOS_FILENAME"
			NON_SECURE_ARCHOS_FULL_PATH="$SYSTEM_NAND_DIR/$ARCHOS_FILENAME"
		fi
	fi
	$MOUNT $SYSTEM_DEV $SYSTEM_DIR -o rw,noatime,nodiratime,noexec || log_and_reboot "mount system fail"
	
}

umountStorage()
{
	if [ $UMOUNT_STORAGE -eq 1 ]; then
		$UMOUNT $STORAGE_DIR || log_and_reboot "umount STORAGE_DIR failed"
	fi

}


prepareFilesystem()
{
	# Run the init-scripts and let mdev setup the device-tree
	/etc/init.d/rcS 
	# Prepare filesystem
	$MOUNT -t proc proc /proc
	$MOUNT -t sysfs sysfs /sys
	$MOUNT -t usbfs usbfs /proc/bus/usb
	
	getProductConfig
}

# gen9 specific functions

install_mass_storage()
{
	case "$PRODUCT_NAME" in
	
		A5H)	log "start the $PRODUCT_NAME SATA HARD DRIVE..."
			install_sata
		;;
		A5*)	#A5S, A5SG, A5GCAM, A5SC, A5ST, A5SGW
			log "start the $PRODUCT_NAME USB HARD DRIVE..."
			install_usbhdd
		;;
		*)	#This should also catch the A48
			log "start the $PRODUCT_NAME SATA HARD DRIVE..."
			install_sata
		;;
	esac


	WAIT_COUNTER=15
	while [  $WAIT_COUNTER -gt 0 ] ; do
		if [ -d /sys/class/scsi_device/0\:0\:0\:0 ] ; then
			break
		fi
		sleep 1
		let WAIT_COUNTER-=1
	done

	if [ $WAIT_COUNTER -eq 0 ] ; then
		MENU_ERROR="install\ hard\ drive\ failed"
		do_proper_reboot
	else
		log "HD ready"
		echo 120 > /proc/hdpwrd/sda/timeout
	fi

}

install_usbhdd()
{
	if [ -e /sys/devices/platform/usbhdd/hddvcc ] ; then
		echo 1 > /sys/devices/platform/usbhdd/hddvcc
		sleep 1
	else
		log "no hddvcc sysfs ?"
	fi
	$INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/host/ehci-hcd.ko
	$INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/storage/usb-storage.ko delay_use=0
}

install_sata()
{
	if [ -e /sys/devices/platform/usb2sata/satavcc ] ; then
		echo 1 > /sys/devices/platform/usb2sata/satavcc
		sleep 1
	else
		log "no satavcc sysfs ?"
	fi
	$INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/host/ehci-hcd.ko
	$INSMOD /lib/modules/$KERNEL_VERSION/kernel/drivers/usb/storage/usb-storage.ko delay_use=0
}


