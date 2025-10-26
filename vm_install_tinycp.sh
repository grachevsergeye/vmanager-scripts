#!/bin/bash
# ==========================================================
# Full TinyCP Installer for Debian/Ubuntu
# ==========================================================

LOG="/var/log/vm_install_tinycp.log"
SUMMARY="/root/tinycp.txt"

exec > >(tee -a "$LOG") 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Installing TinyCP..."

dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y wget curl sudo

wget -qO- https://tinycp.com/install.sh | bash

IP=$(hostname -I | awk '{print $1}')
PASS=$(grep -i "password" "$LOG" | tail -n1 | awk '{print $2}')

cat <<EOF > "$SUMMARY"
✅ TinyCP installed successfully
Panel: http://${IP}:8080
Password: ${PASS:-check in $LOG}
EOF

echo "[OK] TinyCP installation complete."
