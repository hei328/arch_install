#!/bin/bash

# This is an archlinux auto install.
# Before using this script be sure to have an installation medium.
# This script FORMATS YOUR DISK. 
# Use with caution.

# Maybe add a log file

# Backup Reminder
echo "### IMPORTANT ###"
echo "Before proceeding, ensure you have backed up any important data on the disk."
echo "Disk partitioning and formatting operations can lead to data loss."
read -p "Have you backed up your data? (y/n): " backup_confirmation

if [[ "$backup_confirmation" != "y" ]]; then
    echo "Please back up your data before proceeding with the installation."
    exit 1
fi

# Welcome message
echo "##### Welcome to the ArchLinux Installation Script #####"

# Verify Boot Mode
efi_mode=$(cat /sys/firmware/efi/fw_platform_size)
if [ "$efi_mode" -ne 64 ]; then
    echo "Error: The system is not booted in UEFI mode with a 64-bit x64 UEFI."
    echo "Aborting the installation process."
    exit 1
fi

echo "System is booted in UEFI mode with a 64-bit x64 UEFI."

# Update the system clock
echo "Updating the system clock..."
timedatectl set-ntp true

# Partition the disks
echo "Partitioning the disks..."
fdisk -l
echo "Choose the disk to be partitioned (e.g., /dev/sda): "
read disk
echo "Selected disk: $disk"
read -p "Enter the size for the EFI partition (e.g., +300M): " efi_size
read -p "Enter the size for the swap partition (e.g., +2G): " swap_size

# User confirmation before formatting disks
echo "### WARNING ###"
echo "Before proceeding, ensure you have selected the correct disk for partitioning."
echo "All data on the selected disk will be permanently deleted."

# Show selected disk and desired partitioning scheme
echo "Selected disk: $disk"
echo "Desired partitioning scheme:"
echo "  1. EFI System Partition (size: $efi_size)"
echo "  2. Linux Swap Partition (size: $swap_size)"
echo "  3. Linux Root Partition (size: remainder of the device)"

read -p "Have you selected the correct disk and backed up your data? (y/n): " disk_confirmation

if [[ "$disk_confirmation" != "y" ]]; then
    echo "Please double-check your disk selection and back up your data before proceeding."
    exit 1
fi

# Check if the selected disk exists
if [[ ! -e "$disk" ]]; then
    echo "Error: The selected disk '$disk' does not exist."
    exit 1
fi

fdisk "$disk" <<EOF
g    # Create a new GPT partition table
n    # Create a new partition
1    # Partition number (EFI system partition)
    # Default start sector
$efi_size # Size of the EFI partition
n    # Create a new partition
2    # Partition number (Linux swap)
    # Default start sector
$swap_size # Size of the swap partition
n    # Create a new partition
3    # Partition number (Linux root)
    # Default start sector
    # Default size (remainder of the device)
t    # Change partition type
1    # Select the EFI partition
1    # Set type to EFI System
t    # Change partition type
2    # Select the swap partition
19   # Set type to Linux swap
t    # Change partition type
3    # Select the Linux root partition
23   # Set type to Linux x86_64 root (/)
w    # Write changes and exit
EOF

# Format and mount the partitions
echo "Formatting and mounting partitions..."
# Set the partition variables based on your disk and partitioning scheme
efi_partition="/dev/sda1"
swap_partition="/dev/sda2"
root_partition="/dev/sda3"

# Confirm that the partitions have been created successfully
if [[ ! -e "$efi_partition" || ! -e "$swap_partition" || ! -e "$root_partition" ]]; then
    echo "Error: Failed to create partitions. Please check the partitioning process."
    exit 1
fi

# Format and mount the EFI partition
echo "Formatting EFI system partition..."
mkfs.fat -F 32 "$efi_partition" || { echo "Error: Failed to format EFI partition."; exit 1; }
mkdir /mnt/boot
mount "$efi_partition" /mnt/boot

# Format and mount the root partition
echo "Formatting root partition..."
mkfs.ext4 "$root_partition" || { echo "Error: Failed to format root partition."; exit 1; }
mount "$root_partition" /mnt

# Set up swap
echo "Setting up swap..."
mkswap "$swap_partition" || { echo "Error: Failed to set up swap."; exit 1; }
swapon "$swap_partition" || { echo "Error: Failed to enable swap."; exit 1; }

# Check internet connectivity
ping -c 3 bing.com || { echo "Error: No internet connectivity. Please connect to the internet and run the script again."; exit 1; }

# Select the mirrors
echo "Selecting mirrors..."
echo "Enter one or more country names separated by space (e.g., UnitedStates Germany): "
read -a country_names

# Use reflector with user-specified country names
reflector --verbose --protocol https --country "${country_names[@]}" --download-timeout 15 --sort rate --save /etc/pacman.d/mirrorlist || { echo "Error: Mirror selection failed."; exit 1; }

# Install essential packages
echo "Installing essential packages..."
pacstrap /mnt base linux linux-firmware || { echo "Error: Failed to install essential packages."; exit 1; }

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the installed system
echo "Chrooting into the installed system..."
arch-chroot /mnt || { echo "Error: Chroot failed."; exit 1; }

# Essential packages in the chroot environment
echo "Installing essential packages in the chroot environment..."

# Install microcode based on CPU vendor
if grep -q "GenuineIntel" /proc/cpuinfo; then
    pacman -S intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    pacman -S amd-ucode
fi

# Install other essential packages
pacman -S less nano sudo neofetch reflector grub efibootmgr dosfstools os-prober mtools networkmanager || { echo "Error: Failed to install essential packages."; exit 1; }

# Time zone
echo "Setting the time zone..."

# List available countries
echo "Available countries:"
ls /usr/share/zoneinfo

# Prompt for country
echo "Enter your country (e.g., Europe, America, Asia): "
read country

# List available cities for the selected country
echo "Available cities for $country:"
ls "/usr/share/zoneinfo/$country"

# Prompt for city
echo "Enter your city (e.g., Berlin, New_York, Shanghai): "
read city

# Create the symbolic link based on the selected country and city
ln -sf "/usr/share/zoneinfo/$country/$city" /etc/localtime
hwclock --systohc

# Localization
echo "Setting up localization..."
sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Network configuration
echo "Setting up network configuration..."
echo "Enter the hostname: "
read hostname
echo "$hostname" > /etc/hostname
systemctl enable NetworkManager

# Set root password
echo "Setting the root password..."
passwd

# Create a new user
echo "Enter a username for the new user: "
read username

# Set the password for the new user
echo "Setting the password for $username..."
passwd "$username"

# Add the user to the wheel group
usermod -aG wheel "$username"

# Uncomment the wheel group in visudo to allow members to execute any command
echo "Uncommenting the wheel group in visudo to allow members to execute any command..."
sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers

# Grub
echo "Installing and configuring Grub..."
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot || { echo "Error: Grub installation failed."; exit 1; }
grub-mkconfig -o /boot/grub/grub.cfg || { echo "Error: Grub configuration generation failed."; exit 1; }

# Confirm Grub installation
read -p "Grub installation and configuration completed successfully. Press Enter to continue."

# Reminder to remove installation medium
echo "Installation complete. Before starting your system, remember to remove the installation medium (USB, DVD, etc.)."
exit
umount -R /mnt

# Shutdown
echo "Shutting down the system..."
shutdown now
