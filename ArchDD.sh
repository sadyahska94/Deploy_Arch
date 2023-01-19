#!/bin/bash

# Set variables for the script
echo -e "Enter the name of the disk you want to install on\n"
echo -e "/dev/nvme0n1p for SSD, /dev/sda for HDD, /dev/vda for virtmanager\n"
read DISK

# Partition the disk
sfdisk ${DISK} << EOF
label: gpt
size=300M, type=ef00
size=512M, type=8300
size=, type=8300
EOF

# Format the partitions
mkfs.fat -F32 ${DISK}1
mkfs.ext4 ${DISK}2

# LUKS encryption on root partition
cryptsetup luksFormat ${DISK}3
cryptsetup open --type luks ${DISK}3 root

# Format the root partition with btrfs
mkfs.btrfs /dev/mapper/root

# Mount Root volume and creating btrfs subvolumes
mount /dev/mapper/root /mnt
btrfs sub cr /mnt/@
btrfs sub cr /mnt/@home
btrfs sub cr /mnt/@cache
btrfs sub cr /mnt/@log
btrfs sub cr /mnt/@vm
btrfs sub cr /mnt/@tmp
btrfs sub cr /mnt/@docker
btrfs sub cr /mnt/@snapshots

# Unmount Top Level ROOT partition
umount /dev/mapper/root

# Mount ROOT Subvolume @
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@ /dev/mapper/root /mnt

# Create directory for each partitions and subvolumes
mkdir -p /mnt/{boot,home,.snapshots,var/{log,cache,tmp,lib/{libvirt,docker}}}

# Mount the partitions
mount ${DISK}2 /mnt/boot
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@home /dev/mapper/root /mnt/home
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@cache /dev/mapper/root /mnt/var/cache
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@log /dev/mapper/root /mnt/var/log
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@vm /dev/mapper/root /mnt/var/lib/libvirt
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@tmp /dev/mapper/root /mnt/var/tmp
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@docker /dev/mapper/root /mnt/var/lib/docker
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@snapshots /dev/mapper/root /mnt/.snapshots

# Install base packages and generate fstab
pacstrap /mnt base base-devel linux linux-firmware btrfs-progs
genfstab -U -p /mnt >> /mnt/etc/fstab

# Customize the fstab file
sed -i '/subvol/ s/\/$/@/' /mnt/etc/fstab


# chroot into the installed system
arch-chroot /mnt

# Install additional packages and enable services
pacman -S --needed --noconfirm openssh nano networkmanager grub dosfstools mtools os-prober efibootmgr
systemctl enable sshd
systemctl enable NetworkManager

# Edit mkinitcpio.conf and add 'encrypt' between 'block' and 'filesystems'
sed -i 's/block filesystems/block encrypt filesystems/' /etc/mkinitcpio.conf
mkinitcpio -p linux

# Set the timezone and clock
timedatectl set-timezone Asia/Kolkata
hwclock --systohc

# Configure locale, hostname, and user

# Set the locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set the hostname
echo -e "Enter the desired hostname on\n"
read myhostname
echo $myhostname > /etc/hostname

echo "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 myhostname.localdomain myhostname" >> /etc/hosts

echo -e "Enter password for Administrator\n"
passwd

echo -e "Enter name for the new user\n"
read user

useradd -m -g users -G wheel,users,power,audio,storage,input,video $user
echo -e "Enter password for new $user :\n"
passwd $user

# Uncomment wheel group in /etc/sudoers
sed -i 's/^# %wheel/%wheel/' /etc/sudoers

# Set up EFI bootloader
mkdir /boot/EFI
mount ${DISK}1 /boot/EFI

grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck

sed -i 's/GRUB_ENABLE_CRYPTODISK=n/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
echo 'GRUB_CMDLINE_LINUX="cryptdevice='$DISK'3:mapper:allow-discards"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Install desktop environment and additional software
#pacman -S --needed --noconfirm gnome-session gdm gnome-control-center gnome-terminal kitty firefox git
#pacman -S --needed --noconfirm appstream-glib archlinux-appstream-data
#systemctl enable gdm

# Exit chroot and unmount the file systems
exit
umount -l /mnt

# Shut down the system
shutdown now


