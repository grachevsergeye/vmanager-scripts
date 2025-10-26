#!/bin/bash
LOG="/var/log/vm_install_outline.log"
SUMMARY="/root/outline.txt"
exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) Outline full installer ==="
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget sudo docker.io jq || true
systemctl enable --now docker || true

# run upstream Outline server manager installer
bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh) || true

# find the generated access file (server_manager writes access.txt)
ACCESS_FILE=$(find /root /home -name access.txt 2>/dev/null | head -n1)
if [ -n "$ACCESS_FILE" ]; then
  ACCESS_CONTENT=$(cat "$ACCESS_FILE")
else
  ACCESS_CONTENT="(access.txt not found; check $LOG)"
fi

cat > "$SUMMARY" <<EOF
Outline installation finished: $(date)

Access info (first ~100 lines):
$ACCESS_CONTENT
EOF

echo "Outline installer finished."
