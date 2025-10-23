#!/usr/bin/env bash
set -euo pipefail

BRANCH="main"
REPO_URL="https://github.com/SCE-Shamoon-College-of-Engineering/2047-ResearchLab-admin-lab.git"
REPO_DIR="/opt/2047-admin-lab"
ANSIBLE_DIR="${REPO_DIR}/ansible"
STATE_DIR="/etc/2047"
VAULT_PASS_FILE="${STATE_DIR}/.vault-pass"
ANSIBLE_PULL_LOG="/var/log/2047-ansible-pull.log"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)"
  exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y git ansible curl

mkdir -p "$STATE_DIR"
touch "$ANSIBLE_PULL_LOG"

# --- GIT SYNC (best-effort) ---
if [[ -d "$REPO_DIR/.git" ]]; then
  # without net/private repo 
  git -C "$REPO_DIR" fetch --all || true
  git -C "$REPO_DIR" reset --hard "origin/${BRANCH}" || true
else
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR" || true
fi


cat > /etc/systemd/system/2047-firstboot.service <<EOF
[Unit]
Description=2047 Admin Server First Converge
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/ansible-playbook -i $ANSIBLE_DIR/inventory/hosts.ini $ANSIBLE_DIR/playbooks/minimal.yml
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/2047-converge.service <<EOF
[Unit]
Description=2047 Admin Server Converge

[Service]
Type=oneshot
ExecStart=/usr/bin/ansible-playbook -i $ANSIBLE_DIR/inventory/hosts.ini $ANSIBLE_DIR/playbooks/converge.yml
EOF

cat > /etc/systemd/system/2047-converge.timer <<EOF
[Unit]
Description=Run 2047 Converge periodically

[Timer]
OnBootSec=10min
OnUnitActiveSec=30min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable 2047-firstboot.service
systemctl enable 2047-converge.timer
systemctl start 2047-firstboot.service
systemctl start 2047-converge.timer

echo "Bootstrap complete. Logs: $ANSIBLE_PULL_LOG"

