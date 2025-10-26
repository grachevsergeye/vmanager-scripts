#!/bin/bash
LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"
set -e

apt update -y >/dev/null 2>&1
apt install -y curl wget sudo >/dev/null 2>&1

bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) >/dev/null 2>&1

IP=$(hostname -I | awk '{print $1}')
PORT=$(ss -tlnp | grep -m1 x-ui | awk '{print $4}' | sed 's/.*://')
USER="admin"
PASS="admin"

cat <<EOF > "$SUMMARY_FILE"
✅ 3x-ui installed successfully
Panel: http://${IP}:${PORT:-54321}
Username: ${USER}
Password: ${PASS}
EOF
