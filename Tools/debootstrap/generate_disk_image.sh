#!/bin/bash


##set some vars.
target="/mnt/target"
target_hostname="lschlv2"
#target_hostname="ls410d"
machine="Buffalo Linkstation LS-CHLv2"
#machine="Buffalo Linkstation LS410D"
arch="armel"
#arch="armhf"
target_rootpw="changeme"
target_user="debian"
target_userpw="changeme"
#distro="stretch"
distro="buster"

boot_size="512"
swap_size="1024"
root_size="2048"

total_size=$((boot_size+swap_size+root_size+1))

boot_size="+""$boot_size""M"
swap_size="+""$swap_size""M"

has_micon="N"

if [ "$machine" == "Buffalo Terastation Pro II/Live" ] || [ "$machine" == "Buffalo Terastation TS-XEL" ] || [ "$machine" == "Buffalo Nas WXL" ] || [ "$machine" == "Buffalo Terastation III" ] || [ "$machine" == "Buffalo Linkstation Pro/Live" ] || [ "$machine" == "Buffalo/Revogear Kurobox Pro" ]; then
  has_micon="Y"
fi

##now armhf devs

##proably unmount etc in case of unclean exit
umount "$target/boot"
umount "$target/dev"
umount "$target/proc"
umount "$target/sys"
umount "$target/"

##create potential disk
image_name="debian_""$distro""_""$arch"".img"
dd if=/dev/zero of="$image_name" bs=1M count=$total_size

##partition the disk image
fdisk "$image_name" <<EOF

n
p
1

$boot_size
n
p
2

$swap_size
n
p
3


p
w
EOF

##create loop devs out of partitions
losetup -D
losetup -f -P "$image_name"

base_dev="$(losetup | grep $image_name | awk '{print $1}')"
boot_dev="$base_dev""p1"
swap_dev="$base_dev""p2"
root_dev="$base_dev""p3"

mkfs.ext3 -I 128 "$boot_dev"
mkswap "$swap_dev"
mkfs.ext4 "$root_dev"

boot_id="$(blkid -o export $boot_dev | grep -e ^UUID= | awk -F= '{print $2}')"
swap_id="$(blkid -o export $swap_dev | grep -e ^UUID= | awk -F= '{print $2}')"
root_id="$(blkid -o export $root_dev | grep -e ^UUID= | awk -F= '{print $2}')"

##mount them as neeeded
mkdir "$target"
mount "$root_dev" "$target"
mkdir "$target/boot"
mount "$boot_dev" "$target/boot"

qemu-debootstrap --arch "$arch" --include=flash-kernel,haveged,openssh-server,busybox,libpam-systemd,dbus,u-boot-tools "$distro" "$target" http://deb.debian.org/debian/

echo "$machine" > "$target/etc/flash-kernel/machine"

mount -t proc none "$target/proc/"
mount -t sysfs none "$target/sys/"
mount -o bind /dev "$target/dev/"

#add prereq for qemu
cp /usr/bin/qemu-arm-static "$target/usr/bin/"

##generate fstab
echo -e "UUID=$root_id\t/\text4\terrors=remount-ro\t0\t1" >> "$target/etc/fstab"
echo -e "UUID=$boot_id\t/boot\text3\tdefaults\t0\t2" >> "$target/etc/fstab"
echo -e "UUID=$swap_id\tnone\tswap\tsw\t0\t0" >> "$target/etc/fstab"

echo "auto lo" >> "$target/etc/network/interfaces"
echo "iface lo inet loopback" >> "$target/etc/network/interfaces"
echo "" >> "$target/etc/network/interfaces"
echo "allow-hotplug eth0" >> "$target/etc/network/interfaces"
echo "iface eth0 inet dhcp" >> "$target/etc/network/interfaces"

echo "$target_hostname" > "$target/etc/hostname"

##my customixations micon/etc
cp "../micro-evtd-$arch" "$target/usr/local/bin/micro-evtd"
cp -r "../micon_scripts" "$target/usr/local/bin/"
cp ../micon_scripts/*.service "$target/etc/systemd/system/"
chmod 755 "$target/usr/local/bin/micon_scripts/*.py"
cp "../phytool-$arch" "$target/usr/local/bin/phytool"
cp "../phy_restart.sh" "$target/usr/local/bin/"
cp "../ifup-mac.sh" "$target/usr/local/bin/"

##distro specific dtbs
if [ "$distro" == "stretch" ]; then
   cp ../../Stretch/device_trees/*.dtb "$target/etc/flash-kernel/dtbs/"
fi

if [ "$distro" == "buster" ]; then
   cp ../../Buster/device_trees/*.dtb "$target/etc/flash-kernel/dtbs/"
fi

cp ../*.db "$target/usr/share/flash-kernel/db/"

##initrd hooks/config for sure.
echo "BOOT=local" > "$target/usr/share/initramfs-tools/conf.d/localboot"
echo "MODULES=dep" > "$target/etc/initramfs-tools/conf.d/modules"
echo mtdblock >> "$target/etc/modules"
echo m25p80 >> "$target/etc/modules"

cp ../runsize.sh "$target/etc/initramfs-tools/scripts/init-bottom/"

echo "sata_mv" >> "$target/etc/initramfs-tools/modules"
echo "libata" >> "$target/etc/initramfs-tools/modules"

##set users and passwords
echo "#!/bin/bash" >> "$target/users.sh"
echo "passwd << EOF" >>"$target/users.sh"
echo "$target_rootpw" >> "$target/users.sh"
echo "$target_rootpw" >> "$target/users.sh"
echo "EOF" >> "$target/users.sh"

echo "adduser $target_user <<EOF" >> "$target/users.sh"
echo "$target_userpw" >> "$target/users.sh"
echo "$target_userpw" >> "$target/users.sh"
echo "" >> "$target/users.sh"
echo "" >> "$target/users.sh"
echo "" >> "$target/users.sh"
echo "" >> "$target/users.sh"
echo "" >> "$target/users.sh"
echo "Y" >> "$target/users.sh"
echo "EOF" >> "$target/users.sh"

chmod +x "$target/users.sh"
chroot "$target" "/users.sh"
rm "$target/users.sh"

##setup fw_printenv
if [ "$arch" == "armhf" ]; then
  echo '/dev/mtdblock1 0x00000 0x10000 0x10000' > "$target/etc/fw_env.config"
fi


##logic for ifup script, just armhf
if [ "$arch" == "armhf" ]; then
  chroot "$target" /bin/bash -c "ln -s /usr/local/bin/ifup-mac.sh /etc/network/if-pre-up.d/ifup_mac"
fi

##logic for enabling micon services all micon
if [ "$has_micon" == "Y" ]; then
   chroot "$target" /bin/bash -c "ln -s /usr/local/bin/micon_scripts/micon_shutdown.py /lib/systemd/system-shutdown/micon_shutdown.py"
   chroot "$target" /bin/bash -c "systemctl enable micon_boot.service"
   chroot "$target" /bin/bash -c "systemctl enable micon_fan_daemon.service"
else
   chroot "$target" /bin/bash -c "ln -s /usr/local/bin/phy_restart.sh /lib/systemd/system-shutdown/phy_restart.sh"
fi

##logic for which kernel? simple enough.
if [ "$arch" == "armhf" ]; then
   chroot "$target" /bin/bash -c "apt-get -y install linux-image-armmp"
fi

if [ "$arch" == "armel" ]; then
   chroot "$target" /bin/bash -c "apt-get -y install linux-image-marvell"
fi

##umount?
umount "$target/boot"
umount "$target/proc"
umount "$target/sys"
umount "$target/dev"
umount "$target"
losetup -D

