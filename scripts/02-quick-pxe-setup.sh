#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# Quick PXE HTTP setup for lab
# - Proxy-DHCP (port 4011) via dnsmasq (no full DHCP; Fortigate is the DHCP server)
# - HTTPBoot/iPXE over Apache
# - Kernel/initrd served from /var/www/html/ubuntu (symlinks to casper/*)
# ------------------------------

# May be overridden by Make: make pxe-http PXE_HTTP_IP=... NIC_NAME=...
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

# Ensure service uses sane defaults and correct NIC
install -m 0644 -o root -g root "configs/dnsmasq.default" "${DNSMASQ_DEF}"
sed -i "s|enp0s31f6|${NIC_NAME}|g" "${DNSMASQ_DEF}"

# Remove any previous override that could break startup
rm -f /etc/systemd/system/dnsmasq.service.d/override.conf || true
systemctl daemon-reload

echo "[*] Prepare HTTP/TFTP trees..."
mkdir -p "${WWW_ROOT}/EFI/BOOT" "${WWW_ROOT}/ubuntu" "${WWW_ROOT}/autoinstall" "${TFTP_ROOT}"

# Place iPXE fallback loader (UEFI) via TFTP (for clients that do PXE->iPXE chain)
if [ -f /usr/lib/ipxe/ipxe.efi ]; then
  install -m 0644 -o nobody -g nogroup /usr/lib/ipxe/ipxe.efi "${TFTP_ROOT}/ipxe.efi"
fi

# Ensure iPXE script is in HTTP root
install -m 0644 -o www-data -g www-data "www/boot.ipxe" "${WWW_ROOT}/boot.ipxe"

# Ensure autoinstall cloud-init files are present (if tracked in repo)
if [ -f "www/autoinstall/user-data" ]; then
  install -m 0644 -o www-data -g www-data "www/autoinstall/user-data" "${WWW_ROOT}/autoinstall/user-data"
fi
if [ -f "www/autoinstall/meta-data" ]; then
  install -m 0644 -o www-data -g www-data "www/autoinstall/meta-data" "${WWW_ROOT}/autoinstall/meta-data"
fi

# --- Use existing kernel/initrd from local Ubuntu tree (no ISO download) ---
CASPER_DIR="${WWW_ROOT}/ubuntu/casper"

if [ -f "${CASPER_DIR}/vmlinuz" ] && [ -f "${CASPER_DIR}/initrd" ]; then
  echo "[*] Found kernel/initrd under ${CASPER_DIR} – linking to /ubuntu/"
  ln -sf "${CASPER_DIR}/vmlinuz" "${WWW_ROOT}/ubuntu/vmlinuz"
  ln -sf "${CASPER_DIR}/initrd"  "${WWW_ROOT}/ubuntu/initrd"
  chown -h www-data:www-data "${WWW_ROOT}/ubuntu/vmlinuz" "${WWW_ROOT}/ubuntu/initrd" || true

  echo "[*] Copy kernel/initrd to TFTP as optional fallback..."
  mkdir -p "${TFTP_ROOT}/ubuntu"
  cp -f "${CASPER_DIR}/vmlinuz" "${TFTP_ROOT}/ubuntu/vmlinuz"
  cp -f "${CASPER_DIR}/initrd"  "${TFTP_ROOT}/ubuntu/initrd"
  chmod 0644 "${TFTP_ROOT}/ubuntu/vmlinuz" "${TFTP_ROOT}/ubuntu/initrd" || true
else
  echo "[!] ${CASPER_DIR}/vmlinuz or initrd not found. Skipping symlinks."
  echo "[!] HTTP /ubuntu/vmlinuz and /ubuntu/initrd will 404 until casper files exist."
fi

echo "[*] HTTP ubuntu/ contents (expect vmlinuz/initrd symlinks here):"
ls -l "${WWW_ROOT}/ubuntu" || true

# (Optional) Place UEFI shim/boot loader to serve HTTPBoot directly
# Keep this as-is if you already have working files under ${WWW_ROOT}/EFI/BOOT/
# If needed, uncomment the following lines:
# if [ -f /usr/lib/shim/shimx64.efi.signed ] && [ -f /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed ]; then
#   install -m 0644 -o www-data -g www-data /usr/lib/shim/shimx64.efi.signed "${WWW_ROOT}/EFI/BOOT/bootx64.efi"
#   install -m 0644 -o www-data -g www-data /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed "${WWW_ROOT}/EFI/BOOT/grubx64.efi"
# fi

echo "[*] Restart services..."
systemctl restart apache2
systemctl restart dnsmasq || (journalctl -xeu dnsmasq.service --no-pager | tail -n 80; exit 1)

echo "[*] Sanity checks (ports & HTTP endpoints)..."
# Expect UDP :69 (TFTP) and :4011 (Proxy-DHCP). If empty, dnsmasq may still be OK (no TFTP/Proxy-DHCP enabled).
ss -lunp | grep -E ':(69|4011)\b' || true

curl -I "http://${HTTP_IP}/EFI/BOOT/bootx64.efi" || true
curl -I "http://${HTTP_IP}/boot.ipxe" || true
curl -I "http://${HTTP_IP}/ubuntu/vmlinuz" || true
curl -I "http://${HTTP_IP}/ubuntu/initrd" || true
curl -I "http://${HTTP_IP}/autoinstall/user-data" || true

echo "[*] Done."
