#!/bin/bash
# ==========================================================
# TinyCP Full Auto-Installer (Outline-style summary)
# - Installs TinyCP silently
# - Auto-generates or extracts admin password
# - Writes login info to /root/tinycp.txt
# - Displays summary automatically on login
# Logs -> /var/log/vm_install_tinycp.log
# ==========================================================

LOG="/var/log/vm_install_tinycp.log"
SUMMARY="/root/tinycp.txt"
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

# Give TinyCP a few seconds to finish setup
sleep 10

# Detect or set password
PASS=""

# 1️⃣ Try to read password from known places
if [ -f "$PASS_FILE" ]; then
  PASS=$(head -n1 "$PASS_FILE" 2>/dev/null)
elif [ -f "$ACCESS_CONF_1" ]; then
  PASS=$(grep -Eo '"password"\s*:\s*"[^"]+"' "$ACCESS_CONF_1" | head -n1 | cut -d'"' -f4)
elif [ -f "$ACCESS_CONF_2" ]; then
  PASS=$(grep -Eo '"password"\s*:\s*"[^"]+"' "$ACCESS_CONF_2" | head -n1 | cut -d'"' -f4)
fi

# 2️⃣ If not found, generate one and set it
if [ -z "$PASS" ]; then
  PASS=$(pwgen -s 12 1)
  mkdir -p /etc/tinycp /usr/local/tinycp
  CONFIG_TARGET=""

  if [ -f "$ACCESS_CONF_1" ]; then
    CONFIG_TARGET="$ACCESS_CONF_1"
  elif [ -f "$ACCESS_CONF_2" ]; then
    CONFIG_TARGET="$ACCESS_CONF_2"
  fi

  # Try to inject password into TinyCP config
  if [ -n "$CONFIG_TARGET" ]; then
    tmp=$(mktemp)
    jq --arg pw "$PASS" '.password = $pw' "$CONFIG_TARGET" > "$tmp" 2>/dev/null && mv "$tmp" "$CONFIG_TARGET"
  fi

  echo "$PASS" > "$PASS_FILE"
fi

# 3️⃣ Restart TinyCP service if present
systemctl restart tinycp 2>/dev/null || true

# Gather system info
IP=$(hostname -I | awk '{print $1}')
DATE="$(date)"

# Write summary (shown on login)
cat > "$SUMMARY" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo -e "\033[1;32m✅ TinyCP Installation Complete!\033[0m"
echo ""
echo "Date: $DATE"
echo ""
echo "Panel: http://$IP:8080"
echo "Login: admin"
echo "Password: $PASS"
echo ""
echo "=============================================="
echo ""
EOF

chmod +x "$SUMMARY"

# Auto-show summary at root login
BASHRC="/root/.bashrc"
if ! grep -qF "bash /root/tinycp.txt" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# show TinyCP credentials at login" >> "$BASHRC"
  echo "if [ -f /root/tinycp.txt ]; then bash /root/tinycp.txt; fi" >> "$BASHRC"
fi

echo "✅ TinyCP installer finished. Summary written to $SUMMARY"
echo "See full log: $LOG"
