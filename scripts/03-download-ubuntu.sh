#!/bin/bash
# Download and extract Ubuntu 24.04 Desktop ISO for PXE boot
# Usage: sudo ./scripts/03-download-ubuntu.sh

set -euo pipefail

ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso"
ISO_PATH="/tmp/ubuntu-24.04-desktop.iso"
MOUNT_POINT="/mnt/ubuntu-iso"
TARGET_DIR="/var/www/html/ubuntu"
TFTP_DIR="/srv/tftp/ubuntu"

echo "⬇️  Downloading Ubuntu 24.04 Desktop ISO..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

# Download ISO
if [[ ! -f "$ISO_PATH" ]]; then
    echo "Downloading Ubuntu Desktop ISO (this may take 15-20 minutes)..."
    wget --show-progress -O "$ISO_PATH" "$ISO_URL"
else
    echo "ISO already exists at $ISO_PATH, skipping download"
fi

# Mount ISO
echo "📀 Mounting ISO..."
mkdir -p "$MOUNT_POINT"
mount -o loop "$ISO_PATH" "$MOUNT_POINT"

# Copy ISO contents
echo "📋 Copying ISO contents to HTTP directory..."
rsync -a --info=progress2 "$MOUNT_POINT/" "$TARGET_DIR/"

# Copy kernel and initrd for TFTP
echo "📋 Copying kernel and initrd for TFTP..."
mkdir -p "$TFTP_DIR"
cp "$TARGET_DIR/casper/vmlinuz" "$TFTP_DIR/"
cp "$TARGET_DIR/casper/initrd" "$TFTP_DIR/"

# Unmount
echo "📤 Unmounting ISO..."
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

# Set permissions
chown -R www-data:www-data "$TARGET_DIR"
chmod -R 755 "$TARGET_DIR"

echo ""
echo "✅ Ubuntu Desktop ISO extracted successfully!"
echo ""
echo "Files available at:"
echo "  HTTP: http://192.168.1.250/ubuntu/"
echo "  TFTP: /srv/tftp/ubuntu/vmlinuz"
echo "        /srv/tftp/ubuntu/initrd"
echo ""
echo "You can now test PXE boot on a student PC!"
