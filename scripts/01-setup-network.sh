#!/bin/bash
# Configure static IP for PXE server
# Usage: sudo ./scripts/01-setup-network.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "🌐 Configuring static IP for PXE server..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "❌ This script must be run as root"
    exit 1
fi

# Copy netplan config
cp "$REPO_DIR/network/01-netcfg.yaml" /etc/netplan/01-netcfg.yaml

# Set correct permissions
chmod 600 /etc/netplan/01-netcfg.yaml

# Apply configuration
echo "Applying network configuration..."
netplan apply

# Verify
echo ""
echo "✅ Network configured!"
echo "New IP: 192.168.1.250"
echo ""
echo "Verifying..."
ip addr show enp0s31f6 | grep inet

echo ""
echo "✅ Done! Server is now at 192.168.1.250"
