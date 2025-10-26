#!/bin/bash
# Full 3x-ui installer
LOG="/var/log/vm_install_3xui.log"
SUMMARY="/root/3xui.txt"

exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) Starting full 3x-ui install ==="

# fix dpkg / apt
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt upgrade -y || true

# prerequisites
apt install -y curl wget tar lsof net-tools sudo cron || true

# remove problematic fake systemctl if present (some minimal images ship weird packages)
if dpkg -l | grep -q "^ii  systemctl "; then
  apt remove -y systemctl || true
fi

# download + run upstream installer non-interactive
curl -L -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

# run installer and capture output
/tmp/install_3xui.sh <<'ENDINPUT'
n
ENDINPUT

# try start/enable
systemctl enable x-ui || true
systemctl start x-ui || true

# Try to extract credentials from the log (the upstream installer prints them)
sleep 1
IP=$(hostname -I | awk '{print $1}')
# extract common labels (Username/Password/Port/WebBasePath/Access URL)
USER=$(grep -m1 -E 'Username:' "$LOG" | awk -F: '{print $2}' | tr -d ' ')
PASS=$(grep -m1 -E 'Password:' "$LOG" | awk -F: '{print $2}' | tr -d ' ')
PORT=$(grep -m1 -E 'Port:' "$LOG" | awk -F: '{print $2}' | tr -d ' ')
WEBPATH=$(grep -m1 -E 'WebBasePath:' "$LOG" | awk -F: '{print $2}' | tr -d ' ')
ACCESSURL=$(grep -m1 -E 'Access URL:' "$LOG" | sed -n 's/.*Access URL: //p' || true)

cat > "$SUMMARY" <<EOF
3x-ui install finished: $(date)
Access URL: ${ACCESSURL:-http://${IP}:${PORT}${WEBPATH}}
Username: ${USER:-(see log)}
Password: ${PASS:-(see log)}
Port: ${PORT:-(see log)}
EOF

echo "3x-ui installer done."
