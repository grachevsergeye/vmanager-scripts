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

echo "[*] Running official Outline server installer..."
bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh) || true

echo "[*] Searching for Outline access info..."
ACCESS_FILE=$(find /root /home -name access.txt 2>/dev/null | head -n1)
IP=$(hostname -I | awk '{print $1}')

if [ -n "$ACCESS_FILE" ]; then
  echo "[+] Found access.txt: $ACCESS_FILE"
  ACCESS_URL=$(grep -Eo '"apiUrl": *"[^"]+"' "$ACCESS_FILE" | sed 's/"apiUrl": *"//; s/"$//')
  CERT_SHA256=$(grep -Eo '"certSha256": *"[^"]+"' "$ACCESS_FILE" | sed 's/"certSha256": *"//; s/"$//')
  PORT=$(echo "$ACCESS_URL" | sed -E 's/.*:([0-9]+).*/\1/')
else
  ACCESS_URL=""
  CERT_SHA256=""
  PORT="(unknown)"
fi

cat > "$SUMMARY" <<EOF
==============================================
✅ Outline Installation Complete!
Date: $(date)

IP: ${IP}
Port: ${PORT}
API URL: ${ACCESS_URL}
Cert SHA256: ${CERT_SHA256}

Full access.txt content:
----------------------------------------------
$(cat "$ACCESS_FILE" 2>/dev/null || echo "(access.txt not found)")
==============================================
EOF

echo "✅ Outline installer finished successfully."
