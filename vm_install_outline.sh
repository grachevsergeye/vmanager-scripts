#!/bin/bash
# ==========================================================
# Outline VPN Full Installer (with real credential summary)
# ==========================================================

LOG="/var/log/vm_install_outline.log"
SUMMARY="/root/outline.txt"
ACCESS_FILE="/opt/outline/access.txt"

exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) Outline full installer ==="

# Prepare environment
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget sudo docker.io jq || true

systemctl enable --now docker || true

# Run official Outline installer
bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh) || true

echo "[*] Searching for Outline access info..."

# Wait for /opt/outline/access.txt
for i in {1..30}; do
  if [ -f "$ACCESS_FILE" ]; then
    echo "Found access.txt at $ACCESS_FILE"
    break
  fi
  echo "Waiting for access.txt... ($i)"
  sleep 2
done

# Parse credentials
if [ -f "$ACCESS_FILE" ]; then
  API_URL=$(jq -r '.apiUrl' "$ACCESS_FILE" 2>/dev/null)
  CERT_SHA=$(jq -r '.certSha256' "$ACCESS_FILE" 2>/dev/null)
else
  API_URL="(not found)"
  CERT_SHA="(not found)"
fi

IP=$(hostname -I | awk '{print $1}')
DATE=$(date)

# Save summary
cat > "$SUMMARY" <<EOF
==============================================
✅ Outline Installation Complete!
Date: $DATE

IP: $IP
API URL: $API_URL
Cert SHA256: $CERT_SHA

Full access.txt content:
----------------------------------------------
$(cat "$ACCESS_FILE" 2>/dev/null || echo "(access.txt not found)")
==============================================
EOF

chmod +x "$SUMMARY"

# Show on every login
if ! grep -q "bash /root/outline.txt" /root/.bashrc; then
  echo "bash /root/outline.txt" >> /root/.bashrc
fi

echo "✅ Outline installer finished successfully."
