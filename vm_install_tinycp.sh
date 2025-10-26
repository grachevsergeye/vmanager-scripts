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
apt install -y wget curl sudo || true

# run upstream TinyCP installer (this will produce a password in its output/log)
wget -qO- https://tinycp.com/install.sh | bash || true

IP=$(hostname -I | awk '{print $1}')
# try to find password in log
PASS=$(grep -Ei 'password|admin' "$LOG" | tail -n5 | tr '\n' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
[ -z "$PASS" ] && PASS="(see $LOG for details)"

cat > "$SUMMARY" <<EOF
TinyCP installation finished: $(date)
Panel: http://${IP}:8080
Credentials / hints: ${PASS}
EOF

echo "TinyCP installer finished."
