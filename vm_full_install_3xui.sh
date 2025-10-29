#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (auto-detects success + real creds)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"
INSTALLER_URL="https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# Fix apt and install dependencies
dpkg --configure -a >/dev/null 2>&1 || true
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget sudo tar lsof net-tools jq sqlite3 >/dev/null 2>&1

# Download official installer
curl -fsSL -o /tmp/install_3xui.sh "$INSTALLER_URL"
chmod +x /tmp/install_3xui.sh

# Run installation non-interactively
bash /tmp/install_3xui.sh <<EOF | tee -a "$LOG_FILE"
n
EOF

# Wait up to 60s for installation to complete
for i in {1..30}; do
    if [ -d "/usr/local/x-ui" ]; then
        echo "3x-ui installation directory found."
        break
    fi
    echo "Waiting for 3x-ui to appear... ($i)"
    sleep 2
done

# Verify install success
if [ ! -d "/usr/local/x-ui" ]; then
    echo "❌ 3x-ui installation failed. Check $LOG_FILE"
    exit 1
fi

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true
sleep 5

# Try reading from DB (new versions use SQLite)
DB_FILE="/usr/local/x-ui/db/x-ui.db"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"

if [ -f "$DB_FILE" ]; then
    USERNAME=$(sqlite3 "$DB_FILE" "SELECT username FROM users LIMIT_
