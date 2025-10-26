#!/bin/bash
# ==========================================================
# Full 3x-ui Installer for Debian/Ubuntu
# ==========================================================

LOG="/var/log/vm_install_3xui.log"
SUMMARY="/root/3xui.txt"

exec > >(tee -a "$LOG") 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[INFO] Starting full 3x-ui install..."

dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget sudo tar lsof net-tools cron

bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) <<EOF
n
EOF

systemctl enable x-ui || true
systemctl start x-ui || true

IP=$(hostname -I | awk '{print $1}')
PORT=$(ss -tlnp | grep -m1 x-ui | awk '{print $4}' | sed 's/.*://')
PORT=${PORT:-54321}

cat <<EOF > "$SUMMARY"
✅ 3x-ui installed successfully
Panel: http://${IP}:${PORT}
Username: admin
Password: admin
EOF

echo "[OK] 3x-ui installed successfully."
