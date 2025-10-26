#!/bin/bash
# ==========================================================
# Full Outline VPN Installer for Debian/Ubuntu
# ==========================================================

LOG="/var/log/vm_install_outline.log"
SUMMARY="/root/outline.txt"

exec > >(tee -a "$LOG") 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Installing Outline VPN..."

dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget sudo jq docker.io -y

systemctl enable --now docker

bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh) | tee -a "$LOG"

ACCESS=$(find /root /home -name access.txt 2>/dev/null | head -n1)
KEY=$(grep -Eo 'ss://[^ ]+' "$ACCESS" | head -n1)

cat <<EOF > "$SUMMARY"
✅ Outline VPN installed successfully
Access key: ${KEY:-check access.txt}
EOF

echo "[OK] Outline VPN installation complete."
v
