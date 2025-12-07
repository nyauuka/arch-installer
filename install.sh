#!/bin/bash

set -e

clear

#disk selection script
show_disks() {
  echo "Availible disks:"
  lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E '(disk|NAME)'
}

#zone selection
select tz in UTC Europe/Moscow Europe/London Europe/Berlin America/New_York America/Los_Angeles Asia/Tokyo Asia/Shanghai Australia/Sydney; do
    export TZ=$tz
    echo "Choosed ${TZ}"
    break
done
lang=en_US

#choosing password
read -p "Choose root pass: " pass
echo ""

#choosing disk
show_disks

echo ""
read -p "Type disk name(sda/nvme0n1): " disk

#confirmation
echo ""
echo "ATTENTION! ALL DATA WILL BE WIPED!"
read -p "Are you sure?(Y/N): " confirm

if ! [[ $confirm =~ ^[Yy]$ ]]; then
  echo "installing canceled"
  exit 1
fi

clear

#partitoning
DISK=/dev/$disk
SIZE1=1G

#for nvme's
if [[ $DISK == /dev/nvme* ]]; then
  DISKP=${DISK}p
else
  DISKP=${DISK}
fi

#unmounting if mounted
for partition in "${DISKP}1" "${DISKP}2" "${DISKP}3"; do
    if findmnt -S "$partition" >/dev/null 2>&1; then
        umount "$partition"
    fi
done

#disc cleaning
sgdisk -Z $DISK 2>/dev/null || true
wipefs -a $DISK 2>/dev/null || true

fdisk $DISK << end_partitioning
g
n
1

+${SIZE1}
n
2


w
end_partitioning

sleep 2

#filesystem
mkfs.fat -F 32 ${DISKP}1
mkfs.ext4 ${DISKP}2

sleep 3

#mounting
mount ${DISKP}2 /mnt
mkdir -p /mnt/boot
mount ${DISKP}1 /mnt/boot

#base pcgs
pacstrap /mnt base base-devel linux linux-firmware sudo iwd dhcpcd openresolv vim fastfetch
pacstrap /mnt efibootmgr grub os-prober

clear

#fstab
genfstab -U /mnt >> /mnt/etc/fstab

cat > /mnt/chroot_script.sh << 'CHROOT'
#!/bin/bash

set -e

#time
ln -sf /usr/share/zoneinfo/${1} /etc/localtime
hwclock --systohc

#localisation
echo "${2}.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${2}.UTF-8" >> /etc/locale.conf
echo "KEYMAP=us" >> /etc/vconsole.conf

echo "archlinux" > /etc/hostname

#root password set
echo "root:${3}" | chpasswd

#network
echo "127.0.0.1        localhost
::1              localhost
127.0.1.1        archlinux" > /etc/hosts

systemctl enable systemd-resolved
cat > /etc/resolved.conf << doned
[Resolve]
DNS=1.1.1.1 1.0.0.1
FallbackDNS=8.8.8.8 8.8.4.4
doned
rm -f /etc/resolv.conf
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

#turning on servises
systemctl enable iwd
systemctl enable dhcpcd

#bootloader install
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

mkinitcpio -P
CHROOT

clear

#chrooting
chmod +x /mnt/chroot_script.sh
arch-chroot /mnt /chroot_script.sh "$timezone" "$lang" "$pass" "$DISK"
rm /mnt/chroot_script.sh

#rebooting
umount -R /mnt
reboot
