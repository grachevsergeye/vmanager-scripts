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
    USERNAME=$(sqlite3 "$DB_FILE" "SELECT username FROM users LIMIT 1;")
    PASSWORD=$(sqlite3 "$DB_FILE" "SELECT password FROM users LIMIT 1;")
elif [ -f "$CONFIG_FILE" ]; then
    USERNAME=$(jq -r '.webUser // .username // "admin"' "$CONFIG_FILE")
    PASSWORD=$(jq -r '.webPassword // .password // "admin123"' "$CONFIG_FILE")
else
    USERNAME="admin"
    PASSWORD="admin123"
fi

# Port and path
PORT=$(jq -r '.webPort // "54321"' "$CONFIG_FILE" 2>/dev/null || echo "54321")
PATH_ID=$(jq -r '.webBasePath // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
IP=$(hostname -I | awk '{print $1}')

# Save summary
cat <<EOF > "$SUMMARY_FILE"
echo ""
echo -e "\033[1;32m✅ 3x-ui Installation Complete!\033[0m"
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: http://$IP:$PORT/$PATH_ID"
echo ""
EOF
chmod +x "$SUMMARY_FILE"

# Auto-show summary on login
if ! grep -q "bash /root/3xui.txt" /root/.bashrc; then
    echo "bash /root/3xui.txt" >> /root/.bashrc
fi

echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
