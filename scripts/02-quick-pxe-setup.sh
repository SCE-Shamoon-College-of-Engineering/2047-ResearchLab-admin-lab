#!/usr/bin/env bash
set -euo pipefail

# Can be overridden by Make target: make pxe-http PXE_HTTP_IP=...
HTTP_IP="${HTTP_IP:-192.168.1.250}"
NIC_NAME="${NIC_NAME:-enp0s31f6}"

WWW_ROOT="/var/www/html"
TFTP_ROOT="/srv/tftp"
DNSMASQ_D="/etc/dnsmasq.d"
DNSMASQ_DEF="/etc/default/dnsmasq"

echo "[*] Installing packages (dnsmasq, apache2, curl, ipxe)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y dnsmasq apache2 curl ipxe

echo "[*] Configure dnsmasq (Proxy-DHCP + HTTPBoot + iPXE fallback)..."
install -m 0644 -o root -g root "configs/pxe-http.conf" "${DNSMASQ_D}/pxe-http.conf"
sed -i "s|192.168.1.250|${HTTP_IP}|g" "${DNSMASQ_D}/pxe-http.conf"
sed -i "s|interface=enp0s31f6|interface=${NIC_NAME}|g" "${DNSMASQ_D}/pxe-http.conf"

# Ensure service uses sane defaults (no custom override unit)
install -m 0644 -o root -g root "configs/dnsmasq.default" "${DNSMASQ_DEF}"
sed -i "s|enp0s31f6|${NIC_NAME}|g" "${DNSMASQ_DEF}"

# Remove any previous override that could break startup
rm -f /etc/systemd/system/dnsmasq.service.d/override.conf || true
systemctl daemon-reload

echo "[*] Prepare HTTP/TFTP trees..."
mkdir -p "${WWW_ROOT}/EFI/BOOT" "${WWW_ROOT}/ubuntu" "${WWW_ROOT}/autoinstall" "${TFTP_ROOT}"

# Place iPXE fallback loader (UEFI) via TFTP
if [ -f /usr/lib/ipxe/ipxe.efi ]; then
  install -m 0644 -o nobody -g nogroup /usr/lib/ipxe/ipxe.efi "${TFTP_ROOT}/ipxe.efi"
fi

# Ensure iPXE script is in HTTP root
install -m 0644 -o www-data -g www-data "www/boot.ipxe" "${WWW_ROOT}/boot.ipxe"

# --- your existing blocks that put bootx64.efi, vmlinuz, initrd, autoinstall user-data/meta-data ---
# (оставляю как есть, они у тебя уже работают)

echo "[*] Restart services..."
systemctl restart apache2
systemctl restart dnsmasq || (journalctl -xeu dnsmasq.service --no-pager | tail -n 80; exit 1)

echo "[*] Sanity checks (ports & HTTP endpoints)..."
ss -lunp | grep -E ':(69|4011)\b' || true
curl -I "http://${HTTP_IP}/EFI/BOOT/bootx64.efi" || true
curl -I "http://${HTTP_IP}/boot.ipxe" || true
curl -I "http://${HTTP_IP}/ubuntu/vmlinuz" || true
curl -I "http://${HTTP_IP}/autoinstall/user-data" || true
echo "[*] Done."
