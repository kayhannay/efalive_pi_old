# apt install qemu-user-static debootstrap git kpartx

CHROOT_DIR=raspbian-chroot

echo "Bootstrapping base system ..."
debootstrap --no-check-gpg --foreign --arch armhf jessie $CHROOT_DIR https://archive.raspbian.org/raspbian

echo "Prepare chroot environment ..."
#CHROOT_ENVIRONMENT="DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C"
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C
export LANGUAGE=C
export LANG=C

cp /usr/bin/qemu-arm-static $CHROOT_DIR/usr/bin/

echo "Install base system ..."
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR debootstrap/debootstrap --second-stage

echo "Install firmware and Kernel ..."
if [ ! -f firmware.zip ]
then
    wget -q --show-progress -O firmware.zip https://github.com/raspberrypi/firmware/archive/master.zip
fi
unzip -q firmware.zip
#git clone http s://github.com/raspberrypi/firmware.git
cp -R firmware-master/hardfp/opt/* $CHROOT_DIR/opt/
mkdir $CHROOT_DIR/lib/modules/
cp -R firmware-master/modules/* $CHROOT_DIR/lib/modules/

echo "Configure system ..."
cp files/sources.list $CHROOT_DIR/etc/apt/sources.list
cp files/efalive.list $CHROOT_DIR/etc/apt/sources.list.d/
cp files/fstab $CHROOT_DIR/etc/fstab
cp files/hostname $CHROOT_DIR/etc/hostname
cp files/interfaces/* $CHROOT_DIR/etc/network/interfaces.d/

echo "Install additional software ..."
mkdir -p $CHROOT_DIR/tmp/keys
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR wget http://archive.raspbian.org/raspbian.public.key -q --show-progress -O /tmp/keys/raspbian.key
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR wget http://archive.raspberrypi.org/debian/raspberrypi.gpg.key -q --show-progress -O /tmp/keys/raspberrypi.key
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR wget http://efalive.hannay.de/efalive.key -q --show-progress -O /tmp/keys/efalive.key
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt-key add /tmp/keys/efalive.key
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt-key add /tmp/keys/raspberrypi.key
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt-key add /tmp/keys/raspbian.key
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt-key list
#$CHROOT_ENVIRONMENT chroot $CHROOT_DIR wget http://archive.raspberrypi.org/debian/raspberrypi.gpg.key -O - | apt-key add -
#$CHROOT_ENVIRONMENT chroot $CHROOT_DIR wget http://efalive.hannay.de/efalive.key -O - | apt-key add -
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt update

mount -t proc proc ./$CHROOT_DIR/proc
mount -t sysfs sysfs ./$CHROOT_DIR/sys
mount -o bind /dev ./$CHROOT_DIR/dev

$CHROOT_ENVIRONMENT chroot $CHROOT_DIR mount
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt install -y --force-yes efalive lightdm

$CHROOT_ENVIRONMENT chroot $CHROOT_DIR useradd -G sudo,staff,kmem,plugdev -s /bin/bash -d /home/pi -m pi
echo "pi:raspberry" | $CHROOT_ENVIRONMENT chroot $CHROOT_DIR chpasswd
echo "root:livecd" | $CHROOT_ENVIRONMENT chroot $CHROOT_DIR chpasswd
sed -i 's/^#autologin-user=/autologin-user=efa/g' $CHROOT_DIR/etc/lightdm/lightdm.conf
sed -i 's/^#autologin-user-timeout=0/autologin-user-timeout=0/g' $CHROOT_DIR/etc/lightdm/lightdm.conf
sed -i 's/^#user-session=default/user-session=efalive-session/g' $CHROOT_DIR/etc/lightdm/lightdm.conf
cp files/efalive-session.desktop $CHROOT_DIR/usr/share/xsessions/
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR ln -s /home/efa/.xinitrc /home/efa/.xsessionrc
$CHROOT_ENVIRONMENT chroot $CHROOT_DIR apt-get clean

echo "Cleanup ..."
rm -r $CHROOT_DIR/tmp/keys
rm $CHROOT_DIR/usr/bin/qemu-arm-static

for i in $(ps ax | grep qemu-arm-static | grep -v grep | sed -e 's/\([0-9]*\).*/\1/g')
do
    kill $i
done

sleep 5

ps ax

umount --force ./$CHROOT_DIR/proc
umount --force ./$CHROOT_DIR/sys
umount --force ./$CHROOT_DIR/dev


echo "Create image file ..."
IMAGE=efaLivePi_2.3.img
dd if=/dev/zero of=$IMAGE bs=1M count=1500

echo "Partition image file ..."
parted $IMAGE <<EOF
unit b
mklabel msdos
mkpart primary fat32 $(expr 4 \* 1024 \* 1024) $(expr 60 \* 1024 \* 1024 - 1)
mkpart primary ext4 $(expr 60 \* 1024 \* 1024) 100%
print
quit
EOF
LOOPDEV=`losetup -P -f --show $IMAGE`
echo $LOOPDEV

echo "Create file systems in image file ..."
mkdosfs -F 32 ${LOOPDEV}p1 -I
mke2fs -t ext4 -j ${LOOPDEV}p2

echo "Copy root file system into image ..."
mkdir rootfs
mount ${LOOPDEV}p2 rootfs
cp -a $CHROOT_DIR/* rootfs
cp -a firmware-master/hardfp/opt/vc rootfs/opt/
umount rootfs
rm -r rootfs

echo "Copy boot file system into image ..."
mkdir bootfs
mount ${LOOPDEV}p1 bootfs
cp -R firmware-master/boot/* bootfs/
 
sh -c 'cat >bootfs/config.txt<<EOF
kernel=kernel.img
arm_freq=800
core_freq=250
sdram_freq=400
over_voltage=0
gpu_mem=16
EOF
'
 
sh -c 'cat >bootfs/cmdline.txt<<EOF
dwc_otg.lpm_enable=0 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw
EOF
'
 
umount bootfs
rm -r bootfs

losetup -d $LOOPDEV

