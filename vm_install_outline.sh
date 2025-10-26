#!/bin/bash
LOG_FILE="/var/log/vm_install_outline.log"
SUMMARY_FILE="/root/outline.txt"
set -e

apt update -y >/dev/null 2>&1
apt install -y curl wget sudo >/dev/null 2>&1

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
  systemctl enable --now docker >/dev/null 2>&1
fi

bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh) >/dev/null 2>&1

ACCESS=$(find /root /home -name access.txt 2>/dev/null | head -n1)
KEY=$(grep -Eo 'ss://[^ ]+' "$ACCESS" | head -n1)

cat <<EOF > "$SUMMARY_FILE"
✅ Outline VPN installed successfully
Access key: ${KEY:-not found}
EOF
