#!/bin/bash
# Quick PXE Server Setup (without Ansible roles dependency)
# Usage: sudo ./scripts/02-quick-pxe-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Quick PXE Server Setup"
echo "=========================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

# Update system
echo "📦 Updating system packages..."
apt update

# Install essential packages
echo "📦 Installing PXE components..."
apt install -y \
    dnsmasq \
    apache2 \
    nfs-kernel-server \
    git \
    wget \
    curl \
    vim \
    htop \
    net-tools

# Create directories
echo "📁 Creating directory structure..."
mkdir -p /srv/tftp/grub
mkdir -p /srv/tftp/ubuntu
mkdir -p /var/www/html/ubuntu
mkdir -p /var/www/html/autoinstall

# Configure dnsmasq
echo "⚙️  Configuring dnsmasq (Proxy DHCP + TFTP)..."
cat > /etc/dnsmasq.d/pxe.conf << 'EOF'
# PXE configuration for lab
# Interface to listen on
interface=enp0s31f6
bind-interfaces

# Proxy DHCP mode (don't assign IPs, only PXE options)
dhcp-range=192.168.1.250,proxy

# Enable TFTP server
enable-tftp
tftp-root=/srv/tftp

# PXE boot options
dhcp-boot=grubx64.efi
dhcp-option=66,192.168.1.250
dhcp-option=67,grubx64.efi

# PXE service
pxe-service=x86PC,"Network Boot",grubx64.efi

# Logging
log-dhcp
log-queries
EOF

# Restart dnsmasq
systemctl restart dnsmasq
systemctl enable dnsmasq

# Configure Apache
echo "⚙️  Configuring Apache..."
cat > /etc/apache2/conf-available/pxe-listings.conf << 'EOF'
<Directory /var/www/html/ubuntu>
    Options +Indexes +FollowSymLinks
    Require all granted
</Directory>

<Directory /var/www/html/autoinstall>
    Options +Indexes +FollowSymLinks
    Require all granted
</Directory>
EOF

a2enconf pxe-listings
systemctl restart apache2
systemctl enable apache2

# Configure firewall
echo "🔒 Configuring firewall..."
ufw allow 22/tcp comment 'SSH' || true
ufw allow 67/udp comment 'DHCP' || true
ufw allow 69/udp comment 'TFTP' || true
ufw allow 80/tcp comment 'HTTP' || true
ufw allow 4011/udp comment 'PXE ProxyDHCP' || true
echo "y" | ufw enable || true

# Download GRUB EFI
echo "⬇️  Installing GRUB EFI bootloader..."
apt install -y grub-efi-amd64-bin
cp /usr/lib/grub/x86_64-efi/grubx64.efi /srv/tftp/

# Create GRUB config
echo "⚙️  Creating GRUB boot menu..."
cat > /srv/tftp/grub/grub.cfg << 'EOF'
# GRUB PXE Boot Menu
set timeout=30
set default=0

menuentry 'Install Ubuntu 24.04 - Student PC' {
    set gfxpayload=keep
    linux /ubuntu/vmlinuz url=http://192.168.1.250/autoinstall/student-pc.yaml autoinstall ds=nocloud-net\;s=http://192.168.1.250/autoinstall/ ip=dhcp
    initrd /ubuntu/initrd
}

menuentry 'Install Ubuntu 24.04 - Teacher PC' {
    set gfxpayload=keep
    linux /ubuntu/vmlinuz url=http://192.168.1.250/autoinstall/teacher-pc.yaml autoinstall ds=nocloud-net\;s=http://192.168.1.250/autoinstall/ ip=dhcp
    initrd /ubuntu/initrd
}

menuentry 'Boot from local disk' {
    exit
}
EOF

# Generate SSH key for Ansible
echo "🔑 Generating SSH key for Ansible..."
if [[ ! -f /root/.ssh/ansible_ed25519 ]]; then
    ssh-keygen -t ed25519 -f /root/.ssh/ansible_ed25519 -N "" -C "ansible@lab-pxe"
    echo ""
    echo "📋 SSH Public Key (add this to student PCs during autoinstall):"
    cat /root/.ssh/ansible_ed25519.pub
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Basic PXE server setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Server IP: 192.168.1.250"
echo "TFTP: Active on port 69"
echo "HTTP: http://192.168.1.250/"
echo "DHCP Proxy: Active on port 67"
echo ""
echo "Next steps:"
echo "1. Download Ubuntu ISO:"
echo "   sudo $REPO_DIR/scripts/03-download-ubuntu.sh"
echo ""
echo "2. Test PXE boot on one student PC:"
echo "   - Enable network boot in BIOS"
echo "   - Boot from network"
echo "   - Select 'Install Ubuntu 24.04 - Student PC'"
echo ""
echo "3. Monitor logs:"
echo "   journalctl -u dnsmasq -f"
echo ""#!/bin/bash
# Quick PXE Server Setup
# Usage: sudo ./quick-setup.sh

set -euo pipefail

echo "🚀 Quick PXE Server Setup"
echo "=========================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    echo "Please run: sudo $0"
    exit 1
fi

# Update system
echo "📦 Updating system packages..."
apt update -qq

# Install essential packages
echo "📦 Installing PXE components..."
apt install -y \
    dnsmasq \
    apache2 \
    nfs-kernel-server \
    git \
    wget \
    curl \
    vim

# Create directories
echo "📁 Creating directory structure..."
mkdir -p /srv/tftp/grub
mkdir -p /srv/tftp/ubuntu
mkdir -p /var/www/html/ubuntu
mkdir -p /var/www/html/autoinstall

# Configure dnsmasq
echo "⚙️  Configuring dnsmasq..."
cat > /etc/dnsmasq.d/pxe.conf << 'EOF'
# PXE configuration for lab
interface=enp0s31f6
bind-interfaces
dhcp-range=192.168.1.250,proxy
enable-tftp
tftp-root=/srv/tftp
dhcp-boot=grubx64.efi
dhcp-option=66,192.168.1.250
dhcp-option=67,grubx64.efi
pxe-service=x86PC,"Network Boot",grubx64.efi
log-dhcp
log-queries
EOF

# Restart dnsmasq
systemctl restart dnsmasq
systemctl enable dnsmasq

# Configure Apache
echo "⚙️  Configuring Apache..."
cat > /etc/apache2/conf-available/pxe-listings.conf << 'EOF'
<Directory /var/www/html/ubuntu>
    Options +Indexes +FollowSymLinks
    Require all granted
</Directory>

<Directory /var/www/html/autoinstall>
    Options +Indexes +FollowSymLinks
    Require all granted
</Directory>
EOF

a2enconf pxe-listings
systemctl restart apache2
systemctl enable apache2

# Configure firewall
echo "🔒 Configuring firewall..."
ufw allow 22/tcp comment 'SSH'
ufw allow 67/udp comment 'DHCP'
ufw allow 69/udp comment 'TFTP'
ufw allow 80/tcp comment 'HTTP'
ufw allow 4011/udp comment 'PXE ProxyDHCP'
echo "y" | ufw enable || true

# Download GRUB EFI
echo "⬇️  Installing GRUB EFI bootloader..."
apt install -y grub-efi-amd64-bin
cp /usr/lib/grub/x86_64-efi/grubx64.efi /srv/tftp/

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Basic PXE server setup complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Server IP: 192.168.1.250"
echo "TFTP: Active"
echo "HTTP: http://192.168.1.250/"
echo ""
echo "Next steps:"
echo "1. Download Ubuntu ISO: sudo ./scripts/download-ubuntu.sh"
echo "2. Copy autoinstall configs"
echo "3. Test PXE boot on student PC"
echo ""
