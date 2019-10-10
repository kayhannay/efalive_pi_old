#!/bin/bash
# apt install qemu-user-static debootstrap git kpartx

#
# Configuration settings
#
CHROOT_DIR=raspbian-chroot
IMAGE_FILE=efaLive-2.7-pi.img
LOGFILE=build.log
DISTRIBUTION=buster

#
# Environment
#
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C
export LANGUAGE=C
export LANG=C

exec &> >(tee -a "$LOGFILE")

clean() {
    echo "Clean up project (but leave firmware download as is)..."
    rm -r $CHROOT_DIR
    rm -r firmware-master
}

bootstrap_base_system() {
    echo "Bootstrapping base system ..."
    debootstrap --no-check-gpg --foreign --arch armhf $DISTRIBUTION $CHROOT_DIR https://archive.raspbian.org/raspbian
    cp /usr/bin/qemu-arm-static $CHROOT_DIR/usr/bin/
}

install_base_system() {
    echo "Install base system ..."
    chroot $CHROOT_DIR debootstrap/debootstrap --second-stage
}

install_software() {
    echo "Install software ..."

    cp files/sources.list $CHROOT_DIR/etc/apt/sources.list
    cp files/efalive.list $CHROOT_DIR/etc/apt/sources.list.d/
    mkdir -p $CHROOT_DIR/tmp/keys
    wget http://archive.raspbian.org/raspbian.public.key -q --show-progress -O $CHROOT_DIR/tmp/keys/raspbian.key
    wget http://archive.raspberrypi.org/debian/raspberrypi.gpg.key -q --show-progress -O $CHROOT_DIR/tmp/keys/raspberrypi.key
    wget http://efalive.hannay.de/efalive.key -q --show-progress -O $CHROOT_DIR/tmp/keys/efalive.key
    chroot $CHROOT_DIR apt-key add /tmp/keys/efalive.key
    chroot $CHROOT_DIR apt-key add /tmp/keys/raspberrypi.key
    chroot $CHROOT_DIR apt-key add /tmp/keys/raspbian.key
    chroot $CHROOT_DIR apt-key list
    chroot $CHROOT_DIR apt update

    mount -t proc proc ./$CHROOT_DIR/proc
    mount -t sysfs sysfs ./$CHROOT_DIR/sys
    mount -o bind /dev ./$CHROOT_DIR/dev

    chroot $CHROOT_DIR mount
    chroot $CHROOT_DIR apt install -y --force-yes raspberrypi-bootloader raspberrypi-kernel firmware-brcm80211
    chroot $CHROOT_DIR apt install -y --force-yes efalive lightdm raspi-config locales wget
    #oracle-java8-jdk

    chroot $CHROOT_DIR apt-get clean

    for i in $(ps ax | grep qemu-arm-static | grep -v grep | sed -e 's/\([ 0-9]*\).*/\1/g')
    do
        kill $i
    done

    sleep 5

    umount --force ./$CHROOT_DIR/proc
    umount --force ./$CHROOT_DIR/sys
    umount --force ./$CHROOT_DIR/dev
}

configure_system() {
    echo "Configure system ..."
    cp files/fstab $CHROOT_DIR/etc/fstab
    cp files/hostname $CHROOT_DIR/etc/hostname
    cp files/interfaces/* $CHROOT_DIR/etc/network/interfaces.d/
    cp -r files/usr $CHROOT_DIR/
    echo "root:livecd" | chroot $CHROOT_DIR chpasswd
    sed -i 's/^#autologin-user=/autologin-user=efa/g' $CHROOT_DIR/etc/lightdm/lightdm.conf
    sed -i 's/^#autologin-user-timeout=0/autologin-user-timeout=0/g' $CHROOT_DIR/etc/lightdm/lightdm.conf
    sed -i 's/^#user-session=default/user-session=efalive-session/g' $CHROOT_DIR/etc/lightdm/lightdm.conf
    cp files/efalive-session.desktop $CHROOT_DIR/usr/share/xsessions/
    chroot $CHROOT_DIR ln -s /home/efa/.xinitrc /home/efa/.xsessionrc
    cp files/raspbian_libs.conf $CHROOT_DIR/etc/ld.so.conf.d/
    chroot $CHROOT_DIR ldconfig
}

cleanup_system() {
    echo "Cleanup chroot ..."
    rm -r $CHROOT_DIR/tmp/keys
    rm $CHROOT_DIR/usr/bin/qemu-arm-static
}


prepare_image_file() {
    echo "Create image file ..."
    dd if=/dev/zero of=$IMAGE_FILE bs=1M count=2000

    echo "Partition image file ..."
parted $IMAGE_FILE <<EOF
unit b
mklabel msdos
mkpart primary fat32 $(expr 4 \* 1024 \* 1024) $(expr 60 \* 1024 \* 1024 - 1)
mkpart primary ext4 $(expr 60 \* 1024 \* 1024) 100%
print
quit
EOF
}

create_loop_device() {
    LOOPDEV=`losetup -P -f --show $IMAGE_FILE`
    echo "Loop device created: $LOOPDEV"
}

format_image_partitions() {
    echo "Create file systems in image file ..."
    mkdosfs -F 32 ${LOOPDEV}p1 -I
    mke2fs -t ext4 -j ${LOOPDEV}p2
}

copy_data_to_rootfs() {
    echo "Copy root file system into image ..."
    mkdir rootfs
    mount ${LOOPDEV}p2 rootfs
    cp -a $CHROOT_DIR/* rootfs
    rm -r rootfs/boot
    umount rootfs
    rm -r rootfs
}

copy_data_to_bootfs() {
    echo "Copy boot file system into image ..."
    mkdir bootfs
    mount ${LOOPDEV}p1 bootfs
    cp -R ${CHROOT_DIR}/boot/* bootfs/

sh -c 'cat >bootfs/config.txt<<EOF
#kernel=kernel.img

# Frequencies
#arm_freq=800
#core_freq=250
#sdram_freq=400
#over_voltage=0

# Display
#gpu_mem=16
hdmi_blanking=1
#hdmi_mode=1
disable_overscan=1
#overscan_left=16
#overscan_right=16
#overscan_top=16
#overscan_bottom=16

# for more options see http://elinux.org/RPi_config.txt
EOF
'

sh -c 'cat >bootfs/cmdline.txt<<EOF
dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw
EOF
'

    umount bootfs
    rm -r bootfs
}

remove_loop_device() {
    losetup -d $LOOPDEV
}

STEP=0
if [ "x$1" != "x" ]
then
    STEP=$1
fi

case $STEP in
    0)
        echo -e "\n[BUILD] Running step '0'"
        clean
        bootstrap_base_system
        ;&
    1)
        echo -e "\n[BUILD] Running step '1'"
        install_base_system
        ;&
    2)
        echo -e "\n[BUILD] Running step '3'"
        install_software
        ;&
    3)
        echo -e "\n[BUILD] Running step '4'"
        configure_system
        ;&
    4)
        echo -e "\n[BUILD] Running step '5'"
        cleanup_system
        ;&
    5)
        echo -e "\n[BUILD] Running step '6'"
        prepare_image_file
        ;&
    6)
        echo -e "\n[BUILD] Running step '7'"
        create_loop_device
        ;&
    7)
        echo -e "\n[BUILD] Running step '8'"
        format_image_partitions
        ;&
    8)
        echo -e "\n[BUILD] Running step '9'"
        copy_data_to_rootfs
        ;&
    9)
        echo -e "\n[BUILD] Running step '10'"
        copy_data_to_bootfs
        ;&
    10)
        echo -e "\n[BUILD] Running step '11'"
        remove_loop_device
        ;;
    *)
        echo -e "\n\nUnknown step '$STEP' provided. Valid steps are 0 - 11.\n"
        exit 1
        ;;
esac

