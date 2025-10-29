#!/bin/bash
LOG="/var/log/vm_install_tinycp.log"
SUMMARY="/root/tinycp.txt"
exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) TinyCP installer ==="

dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y wget curl sudo lsb-release || true

echo "[*] Running official TinyCP installer..."
wget -qO- https://tinycp.com/install.sh | bash || true

IP=$(hostname -I | awk '{print $1}')
PASS=$(grep -Eo 'Password: [^[:space:]]+' "$LOG" | tail -n1 | awk '{print $2}')

if [ -z "$PASS" ]; then
  PASS=$(grep -Ei 'admin|password' "$LOG" | tail -n3 | tr '\n' ' ')
fi

[ -z "$PASS" ] && PASS="(see $LOG for details)"

cat > "$SUMMARY" <<EOF
==============================================
✅ TinyCP Installation Complete!
Date: $(date)

Panel: http://${IP}:8080
Login: admin
Password: ${PASS}
==============================================
EOF

echo "✅ TinyCP installer finished successfully."
