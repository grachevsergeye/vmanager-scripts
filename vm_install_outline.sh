#!/bin/bash
# ==========================================================
# Outline VPN Full Installer (writes console summary on login)
# - Runs official Outline server installer
# - Waits for /opt/outline/access.txt and parses it
# - Creates /root/outline.txt which prints the credentials
# - Ensures /root/outline.txt runs on each root login
# Logs -> /var/log/vm_install_outline.log
# ==========================================================

LOG="/var/log/vm_install_outline.log"
SUMMARY="/root/outline.txt"
ACCESS_FILE="/opt/outline/access.txt"

exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) Outline full installer started ==="

# quick repairs & deps
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget sudo docker.io jq || true

# ensure docker running
systemctl enable --now docker || true

# run the upstream installer (it installs into /opt/outline)
echo "[*] Running official Outline installer..."
bash <(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-apps/master/server_manager/install_scripts/install_server.sh) || true

echo "[*] Waiting for /opt/outline/access.txt to appear..."
# Wait up to ~120s for access file (30 x 4s)
FOUND=0
for i in {1..30}; do
  if [ -f "$ACCESS_FILE" ]; then
    FOUND=1
    echo "Found $ACCESS_FILE"
    break
  fi
  echo "Waiting for access.txt... attempt $i"
  sleep 4
done

if [ "$FOUND" -ne 1 ]; then
  echo "WARNING: access.txt not found at $ACCESS_FILE after wait. Check $LOG for details."
fi

# Parse credentials from /opt/outline/access.txt
API_URL=""
CERT_SHA=""

if [ -f "$ACCESS_FILE" ]; then
  # support both "apiUrl:..." and "apiUrl=..." variants if they ever appear
  API_URL=$(grep -iE '^(apiUrl|apiurl|api_url)[:=]' "$ACCESS_FILE" 2>/dev/null | head -n1 | sed -E 's/^[^:=]+[:=]\s*//I')
  CERT_SHA=$(grep -iE '^(certSha256|certsha256|cert_sha256)[:=]' "$ACCESS_FILE" 2>/dev/null | head -n1 | sed -E 's/^[^:=]+[:=]\s*//I')
fi

# Fallback messages
[ -z "$API_URL" ] && API_URL="(not found)"
[ -z "$CERT_SHA" ] && CERT_SHA="(not found)"

IP=$(hostname -I | awk '{print $1}')
DATE="$(date)"

# Create the console/show script (will run at login)
cat > "$SUMMARY" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo -e "\033[1;32m✅ Outline Installation Complete!\033[0m"
echo ""
echo "Date: $DATE"
echo ""
echo "IP: $IP"
echo "API URL: $API_URL"
echo "Cert SHA256: $CERT_SHA"
echo ""
echo "Full access.txt content (if present):"
echo "----------------------------------------------"
cat "$ACCESS_FILE" 2>/dev/null || echo "(access.txt not present)"
echo "=============================================="
echo ""
EOF

chmod +x "$SUMMARY"

# Ensure the summary runs at root login (append to .bashrc once)
BASHRC="/root/.bashrc"
if ! grep -qF "bash /root/outline.txt" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# show Outline credentials at login" >> "$BASHRC"
  echo "if [ -f /root/outline.txt ]; then bash /root/outline.txt; fi" >> "$BASHRC"
fi

echo "✅ Outline installer finished. Summary written to $SUMMARY"
echo "See full log: $LOG"
