#!/bin/bash
LOG_FILE="/var/log/vm_install_tinycp.log"
SUMMARY_FILE="/root/tinycp.txt"

exec > >(tee -a "$LOG_FILE") 2>&1
set -e

error_exit() {
  echo "❌ ERROR: $1" | tee "$SUMMARY_FILE"
  exit 1
}

echo "=== Installing TinyCP $(date) ==="
apt-get update -y || error_exit "apt update failed"
apt-get install -y wget curl sudo || error_exit "deps failed"

wget -qO- https://tinycp.com/install.sh | bash || error_exit "TinyCP install failed"

IP=$(hostname -I | awk '{print $1}')
PASS=$(grep -i "password" "$LOG_FILE" | tail -n1 | awk '{print $2}')

cat <<EOF > "$SUMMARY_FILE"
✅ TinyCP installed successfully!
Panel: http://${IP}:8080
Password: ${PASS:-check log}
EOF
echo "Summary saved to $SUMMARY_FILE"
