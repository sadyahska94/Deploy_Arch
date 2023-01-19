#!/bin/bash

# Set variables for the script
DISK="/dev/vda"

#yes | sfdisk ${DISK} << EOF; label: gpt; size=512M, type=ef00; size=11G, type=8300; EOF
echo -e "o\nn\np\n1\n\n+512M\nt\n1\nn\np\n2\n\n+11G\nt\n2\n8300\nw\n" | fdisk ${DISK}

# Format the partitions
mkfs.fat -F32 ${DISK}1
mkfs.btrfs -L Root ${DISK}2

# Mount Root volume and creating btrfs subvolumes
mount ${DISK}2 /mnt
btrfs sub cr /mnt/@
btrfs sub cr /mnt/@home
btrfs sub cr /mnt/@cache
btrfs sub cr /mnt/@log
btrfs sub cr /mnt/@vm
btrfs sub cr /mnt/@tmp
btrfs sub cr /mnt/@docker
btrfs sub cr /mnt/@snapshots

# Unmount Top Level ROOT partition
umount ${DISK}2 

# Mount ROOT Subvolume @
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@ ${DISK}2 /mnt

# Create directory for each partitions and subvolumes
mkdir -p /mnt/{boot,home,.snapshots,var/{log,cache,tmp,lib/{libvirt,docker}}}

# Mount the partitions
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@home ${DISK}2 /mnt/home
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@cache ${DISK}2 /mnt/var/cache
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@log ${DISK}2 /mnt/var/log
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@vm ${DISK}2 /mnt/var/lib/libvirt
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@tmp ${DISK}2 /mnt/var/tmp
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@docker ${DISK}2 /mnt/var/lib/docker
mount -o noatime,autodefrag,space_cache=v2,compress=zstd:3,subvol=@snapshots ${DISK}2 /mnt/.snapshots

# Install base packages and generate fstab
yes | pacstrap /mnt base base-devel linux linux-firmware btrfs-progs
genfstab -U -p /mnt >> /mnt/etc/fstab

# Customize the fstab file
sed -i '/subvol/ s/\/$/@/' /mnt/etc/fstab


# chroot into the installed system
arch-chroot /mnt

# Install additional packages and enable services
pacman -S --needed --noconfirm openssh nano networkmanager grub dosfstools mtools os-prober efibootmgr
systemctl enable sshd
systemctl enable NetworkManager

# Set the timezone and clock
timedatectl set-timezone Asia/Kolkata
hwclock --systohc

# Configure locale, hostname, and user

# Set the locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set the hostname
echo "myhostname" > /etc/hostname

echo "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 myhostname.localdomain myhostname" >> /etc/hosts

echo "newpassword" | sudo passwd --stdin root

useradd -m -g users -G wheel,users,power,audio,storage,input,video user

echo "password" | passwd --stdin user

# Uncomment wheel group in /etc/sudoers
sed -i 's/^# %wheel/%wheel/' /etc/sudoers

# Set up EFI bootloader
mkdir /boot/EFI
mount /dev/${DISK}1 /boot/EFI

grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck

# Install desktop environment and additional software
#pacman -S --needed --noconfirm gnome-session gdm gnome-control-center gnome-terminal kitty firefox git
#pacman -S --needed --noconfirm appstream-glib archlinux-appstream-data
#systemctl enable gdm

# Exit chroot and unmount the file systems
exit
umount -l /mnt

# Shut down the system
shutdown now


