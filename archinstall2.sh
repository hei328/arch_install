#!/bin/bash

# This is an archlinux auto install.
# Before using this script be sure to have an installation medium.
# This script FORMATS YOUR DISK. 
# Use with caution.

### Maybe add a log file
### Maybe add checkpoints
### Commented out reflector command
### Commented out grub installation confirmation
### Added heredoc to chroot
### Added sleep 30 to end of script

# Log file location
LOG_FILE="/root/logfile.log"

# Create the log file if it doesn't exist
touch "$LOG_FILE"

# Redirect stdout and stderr to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

if [ "$(tput colors)" -ge 8 ]; then
    # Terminal supports colors
    RED=$(tput setaf 1)
    NC=$(tput sgr0) # Reset color
else
    # Terminal does not support colors
    echo "This terminal does not support colors."
fi

# Backup Reminder
echo -e "${RED}### IMPORTANT ###${NC}"
echo "Before proceeding, ensure you have backed up any important data on the disk."
echo "Disk partitioning and formatting operations can lead to data loss."
read -p "${RED}Have you backed up your data?(y/n): ${NC}" backup_confirmation

if [[ "$backup_confirmation" != "y" ]]; then
    echo "Please back up your data before proceeding with the installation."
    exit 1
fi

# Welcome message
echo -e "${RED}##### Welcome to the ArchLinux Installation Script #####${NC}"

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
echo -e "${RED}Choose the disk to be partitioned (e.g., /dev/sda): ${NC}"
read disk
echo "Selected disk: $disk"
read -p "Enter the size for the EFI partition (e.g., +300M): " efi_size
read -p "Enter the size for the swap partition (e.g., +2G): " swap_size

# User confirmation before formatting disks
echo -e "${RED}### WARNING ###${NC}"
echo "Before proceeding, ensure you have selected the correct disk for partitioning."
echo "All data on the selected disk will be permanently deleted."

# Show selected disk and desired partitioning scheme
echo "Selected disk: $disk"
echo "Desired partitioning scheme:"
echo "  1. EFI System Partition (size: $efi_size)"
echo "  2. Linux Swap Partition (size: $swap_size)"
echo "  3. Linux Root Partition (size: remainder of the device)"

read -p "${RED}Have you selected the correct disk and backed up your data? (y/n): ${NC}" disk_confirmation

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
g
n
1

$efi_size
n
2

$swap_size
n
3


t
1
1
t
2
19
t
3
23
p
w
EOF

# Prompt for confirmation
read -p "${RED}Is the partition table correct? (y/n): ${NC}" confirm
if [ "$confirm" != "y" ]; then
    echo "Aborted by user. Exiting..."
    exit 1
fi

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

# Use reflector with user-specified country names ####OMITTED#### --country "${country_names}"
#reflector --verbose --protocol https --download-timeout 10 --sort rate --save /etc/pacman.d/mirrorlist || { echo "Error: Mirror selection failed."; exit 1; }

# Upgrades the keyring package first
echo "Upgrading keyring package..."
pacman -Sy archlinux-keyring

# Install essential packages
echo "Installing essential packages..."
pacstrap /mnt base linux linux-firmware || { echo "Error: Failed to install essential packages."; exit 1; }

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

### Prepare variables for chroot

# List available countries
echo "Available countries:"
ls /mnt/usr/share/zoneinfo

# Prompt for country
echo -e "${RED}Enter your country (e.g., Europe, America, Asia): ${NC}"
read country

# List available cities for the selected country
echo "Available cities for $country:"
ls "/mnt/usr/share/zoneinfo/$country"

# Prompt for city
echo -e "${RED}Enter your city (e.g., Berlin, New_York, Shanghai): ${NC}"
read city

# Network configuration
echo "Setting up network configuration..."
echo -e "${RED}Enter the hostname: ${NC}"
read hostname

# Set root password
echo -e "${RED}Setting the root password...${NC}"
read -s rootpass

# Create a new user
echo -e "${RED}Enter a username for the new user: ${NC}"
read username

# Set the password for the new user
echo -e "${RED}Setting the password for $username...${NC}"
read -s userpass


set -e # Debugging

# Chroot into the installed system
echo "Chrooting into the installed system..."
arch-chroot /mnt <<EOF
echo "Installing essential packages in the chroot environment..."
if grep -q "GenuineIntel" /proc/cpuinfo; then
    pacman -S --noconfirm intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    pacman -S --noconfirm amd-ucode
fi
pacman -S --noconfirm less nano sudo neofetch reflector grub efibootmgr dosfstools os-prober mtools networkmanager || { echo "Error: Failed to install essential packages."; exit 1; }
echo "Setting the time zone..."
ln -sf "/usr/share/zoneinfo/$country/$city" /etc/localtime
hwclock --systohc
echo "Setting up localization..."
sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "Setting up network configuration..."
echo "$hostname" > /etc/hostname
systemctl enable NetworkManager
echo -e "${RED}Setting the root password...${NC}"
passwd "$rootpass"
echo -e "${RED}Creating the new user... ${NC}"
useradd "$username"
echo -e "${RED}Setting the password for $username...${NC}"
passwd "$username" "$userpass"
usermod -aG wheel "$username"
echo "Uncommenting the wheel group in visudo to allow members to execute any command..."
sed -i '/%wheel ALL=(ALL) ALL/s/^#//' /etc/sudoers
echo "Installing and configuring Grub..."
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot
grub-mkconfig -o /boot/grub/grub.cfg
echo "Installation complete. Before starting your system, remember to remove the installation medium (USB, DVD, etc.)."
exit
EOF
