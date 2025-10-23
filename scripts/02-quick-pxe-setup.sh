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

# --- Kernel/initrd provisioning for HTTP and TFTP ---
ISO_PATH="/tmp/ubuntu-24.04.1-live-server-amd64.iso"  # use server ISO for autoinstall
MNT_DIR="/mnt/ubuntu-iso"

mkdir -p "${WWW_ROOT}/ubuntu" "${TFTP_ROOT}/ubuntu"

# If kernel already present, keep it (idempotent run)
if [ ! -f "${WWW_ROOT}/ubuntu/vmlinuz" ] || [ ! -f "${WWW_ROOT}/ubuntu/initrd" ]; then
  echo "[*] Kernel/initrd not found under ${WWW_ROOT}/ubuntu - ensuring ISO is available..."
  if [ ! -f "${ISO_PATH}" ]; then
    echo "[*] Downloading Ubuntu 24.04.1 live-server ISO (approx 2.2GB)..."
    # Official mirrors; pick one that works in your network. Fallbacks are chained with '||'
    curl -L --fail -o "${ISO_PATH}" \
      "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-live-server-amd64.iso" \
      || curl -L --fail -o "${ISO_PATH}" \
      "http://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.1-live-server-amd64.iso"
  fi

  echo "[*] Mounting ISO ${ISO_PATH}..."
  mkdir -p "${MNT_DIR}"
  # mount may already be active from previous runs; ignore errors
  mount -o loop,ro "${ISO_PATH}" "${MNT_DIR}" || true

  echo "[*] Copying kernel and initrd from ISO casper/ to HTTP directory..."
  # Both Desktop and Server ISOs place kernel/initrd under 'casper/'
  cp -f "${MNT_DIR}/casper/vmlinuz" "${WWW_ROOT}/ubuntu/vmlinuz"
  cp -f "${MNT_DIR}/casper/initrd"  "${WWW_ROOT}/ubuntu/initrd"
  chown -R www-data:www-data "${WWW_ROOT}/ubuntu"
  chmod 0644 "${WWW_ROOT}/ubuntu/vmlinuz" "${WWW_ROOT}/ubuntu/initrd"

  echo "[*] Copying the same kernel/initrd to TFTP directory (optional fallback)..."
  cp -f "${WWW_ROOT}/ubuntu/vmlinuz" "${TFTP_ROOT}/ubuntu/vmlinuz"
  cp -f "${WWW_ROOT}/ubuntu/initrd"  "${TFTP_ROOT}/ubuntu/initrd"
  chmod 0644 "${TFTP_ROOT}/ubuntu/vmlinuz" "${TFTP_ROOT}/ubuntu/initrd"

  echo "[*] Unmounting ISO..."
  umount "${MNT_DIR}" || true
fi

echo "[*] HTTP ubuntu/ contents:"
ls -lh "${WWW_ROOT}/ubuntu" || true


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
