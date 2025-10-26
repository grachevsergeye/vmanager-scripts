#!/bin/bash
LOG_FILE="/var/log/vm_install_tinycp.log"
SUMMARY_FILE="/root/tinycp.txt"
set -e

apt update -y >/dev/null 2>&1
apt install -y wget curl sudo >/dev/null 2>&1

wget -qO- https://tinycp.com/install.sh | bash >/dev/null 2>&1

IP=$(hostname -I | awk '{print $1}')
PASS=$(grep -i "password" "$LOG_FILE" | tail -n1 | awk '{print $2}')

cat <<EOF > "$SUMMARY_FILE"
✅ TinyCP installed successfully
Panel: http://${IP}:8080
Password: ${PASS:-check in log}
EOF
