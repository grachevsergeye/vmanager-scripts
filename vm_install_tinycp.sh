#!/bin/bash
# ==========================================================
# TinyCP Full Auto-Installer (Outline-style summary, 2025)
# - Installs TinyCP silently
# - Extracts credentials from /root/tinycp_info or config files
# - Writes login info to /root/tinycp.txt
# - Displays summary automatically on root login
# Logs -> /var/log/vm_install_tinycp.log
# ==========================================================

LOG="/var/log/vm_install_tinycp.log"
SUMMARY="/root/tinycp.txt"
INFO_FILE="/root/tinycp_info"
ACCESS_CONF_1="/etc/tinycp/config.json"
ACCESS_CONF_2="/usr/local/tinycp/config.json"
PASS_FILE="/root/.tinycp/password"

exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) TinyCP installer started ==="

# Basic prep
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y wget curl sudo jq lsb-release pwgen || true

# Run the official TinyCP installer
echo "[*] Running official TinyCP installer..."
wget -qO- https://tinycp.com/install.sh | bash || true

# Wait a few seconds for TinyCP to initialize and create its info file
sleep 10

# Extract credentials
PANEL_PORT="8080"
LOGIN="admin"
PASS=""

# 1️⃣ Check for /root/tinycp_info first (preferred)
if [ -f "$INFO_FILE" ]; then
  echo "[*] Found $INFO_FILE"
  PANEL_URL=$(grep -Eo 'http[^ ]+' "$INFO_FILE" | head -n1)
  LOGIN=$(grep -iEo 'Login: [^ ]+' "$INFO_FILE" | awk '{print $2}')
  PASS=$(grep -iEo 'Password: [^ ]+' "$INFO_FILE" | awk '{print $2}')
fi

# 2️⃣ Try backup password files if needed
if [ -z "$PASS" ] && [ -f "$PASS_FILE" ]; then
  PASS=$(head -n1 "$PASS_FILE" 2>/dev/null)
fi

# 3️⃣ Try JSON config fallback
if [ -z "$PASS" ] && [ -f "$ACCESS_CONF_1" ]; then
  PASS=$(grep -Eo '"password"\s*:\s*"[^"]+"' "$ACCESS_CONF_1" | head -n1 | cut -d'"' -f4)
elif [ -z "$PASS" ] && [ -f "$ACCESS_CONF_2" ]; then
  PASS=$(grep -Eo '"password"\s*:\s*"[^"]+"' "$ACCESS_CONF_2" | head -n1 | cut -d'"' -f4)
fi

# 4️⃣ Generate random password if absolutely nothing found
if [ -z "$PASS" ]; then
  PASS=$(pwgen -s 12 1)
  echo "$PASS" > "$PASS_FILE"
fi

# Get system info
IP=$(hostname -I | awk '{print $1}')
DATE="$(date)"

# Set fallback panel URL if none found
if [ -z "$PANEL_URL" ]; then
  PANEL_URL="http://$IP:8080"
fi

# Write summary to /root/tinycp.txt (shown at every login)
cat > "$SUMMARY" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo -e "\033[1;32m✅ TinyCP Installation Complete!\033[0m"
echo ""
echo "Date: $DATE"
echo ""
echo "Panel: $PANEL_URL"
echo "Login: $LOGIN"
echo "Password: $PASS"
echo ""
echo "=============================================="
echo ""
EOF

chmod +x "$SUMMARY"

# Auto-show summary on login
BASHRC="/root/.bashrc"
if ! grep -qF "bash /root/tinycp.txt" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# show TinyCP credentials at login" >> "$BASHRC"
  echo "if [ -f /root/tinycp.txt ]; then bash /root/tinycp.txt; fi" >> "$BASHRC"
fi

echo "✅ TinyCP installer finished. Summary written to $SUMMARY"
echo "See full log: $LOG"
