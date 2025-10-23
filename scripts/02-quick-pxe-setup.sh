#!/usr/bin/env bash
set -euo pipefail

HTTP_IP="${HTTP_IP:-192.168.1.250}"   # IP PXE сервера
NIC_NAME="${NIC_NAME:-enp0s31f6}" 

WWW_ROOT="/var/www/html"
TFTP_ROOT="/srv/tftp"
DNSMASQ_D="/etc/dnsmasq.d"
DNSMASQ_DEF="/etc/default/dnsmasq"

echo "[*] Installing packages (dnsmasq, apache2, curl)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y dnsmasq apache2 curl

echo "[*] Configure dnsmasq for HTTP-boot..."
install -m 0644 -o root -g root "configs/pxe-http.conf" "${DNSMASQ_D}/pxe-http.conf"
sed -i "s|192.168.1.250|${HTTP_IP}|g" "${DNSMASQ_D}/pxe-http.conf"
sed -i "s|interface=enp0s31f6|interface=${NIC_NAME}|g" "${DNSMASQ_D}/pxe-http.conf"

echo "[*] Prepare TFTP and HTTP trees..."
mkdir -p "${TFTP_ROOT}" "${WWW_ROOT}/EFI/BOOT" "${WWW_ROOT}/ubuntu" "${WWW_ROOT}/autoinstall"
install -m 0644 -o nobody -g nogroup "tftp/grub.cfg" "${TFTP_ROOT}/grub.cfg"

# Попробуем взять системный grubx64.efi (путь может отличаться на разных дистрибутивах)
GRUB_SRC=""
for p in \
  /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi \
  /usr/lib/grub/x86_64-efi/grubx64.efi \
  /usr/lib/shim/shimx64.efi; do
  [[ -f "$p" ]] && GRUB_SRC="$p" && break
done

if [[ -z "${GRUB_SRC}" ]]; then
  echo "[!] grubx64.efi not found. Install grub-efi-amd64-bin or shim-signed."
  apt-get install -y grub-efi-amd64-bin shim-signed || true
  for p in /usr/lib/grub/x86_64-efi/monolithic/grubx64.efi /usr/lib/grub/x86_64-efi/grubx64.efi /usr/lib/shim/shimx64.efi; do
    [[ -f "$p" ]] && GRUB_SRC="$p" && break
  done
fi

if [[ -n "${GRUB_SRC}" ]]; then
  install -m 0644 -o www-data -g www-data "${GRUB_SRC}" "${WWW_ROOT}/EFI/BOOT/bootx64.efi"
else
  echo "[!] Still no EFI loader; continue, but HTTP-boot will fail until you add bootx64.efi."
fi

echo "[*] Place autoinstall user-data / meta-data..."
install -m 0644 -o www-data -g www-data "www/autoinstall/user-data" "${WWW_ROOT}/autoinstall/user-data"
install -m 0644 -o www-data -g www-data "www/autoinstall/meta-data" "${WWW_ROOT}/autoinstall/meta-data"
sed -i "s|http://192.168.1.250|http://${HTTP_IP}|g" "${WWW_ROOT}/autoinstall/user-data"

echo "[*] Kernel/initrd provisioning..."
mkdir -p "${WWW_ROOT}/ubuntu"
# Если твой scripts/03-download-ubuntu.sh уже знает правильные URL — используем его.
if [[ -x "scripts/03-download-ubuntu.sh" ]]; then
  HTTP_DST="${WWW_ROOT}/ubuntu" bash "scripts/03-download-ubuntu.sh" || true
fi

chown -R www-data:www-data "${WWW_ROOT}"
chown -R nobody:nogroup "${TFTP_ROOT}"

echo "[*] Restart services..."
systemctl restart apache2
systemctl restart dnsmasq

echo "[*] Sanity checks:"
curl -I "http://${HTTP_IP}/EFI/BOOT/bootx64.efi" || true
curl -I "http://${HTTP_IP}/ubuntu/vmlinuz" || true
curl -I "http://${HTTP_IP}/autoinstall/user-data" || true

echo "[*] Tailing logs (hit Ctrl+C to stop):"
echo "    journalctl -u dnsmasq -f"
echo "    tail -f /var/log/apache2/access.log"
