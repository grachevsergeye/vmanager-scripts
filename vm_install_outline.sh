#!/bin/bash
LOG_FILE="/var/log/vm_install_outline.log"
SUMMARY_FILE="/root/outline.txt"

exec > >(tee -a "$LOG_FILE") 2>&1
set -e

error_exit() {
  echo "❌ ERROR: $1" | tee "$SUMMARY_FILE"
  exit 1
}

echo "=== Installing Outline VPN $(date) ==="
apt-get update -y || error_exit "apt update failed"
apt-get install -y curl wget sudo || error_exit "deps failed"

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh || error_exit "Docker install failed"
  systemctl enable docker && systemctl start docker
fi

bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh) || error_exit "Outline install failed"

ACCESS=$(find /root /home -name access.txt 2>/dev/null | head -n1)
KEY=$(grep -Eo 'ss://[^ ]+' "$ACCESS" | head -n1)

cat <<EOF > "$SUMMARY_FILE"
✅ Outline VPN installed successfully!
Access key: ${KEY:-not found}
EOF
echo "Summary saved to $SUMMARY_FILE"
