#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (diagnostic version)
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
apt-get install -y curl wget sudo tar lsof net-tools jq sqlite3 iproute2 >/dev/null 2>&1

# Download and run installer
echo "Downloading official 3x-ui installer..." | tee -a "$LOG_FILE"
curl -fsSL -o /tmp/install_3xui.sh "$INSTALLER_URL"
chmod +x /tmp/install_3xui.sh

echo "Running installer..." | tee -a "$LOG_FILE"
bash /tmp/install_3xui.sh <<EOF | tee -a "$LOG_FILE"
n
EOF

# Check for install
if [ ! -d "/usr/local/x-ui" ]; then
    echo "❌ Installation failed: /usr/local/x-ui not found" | tee -a "$LOG_FILE"
    echo "--- LAST 30 LINES OF LOG ---" | tee -a "$LOG_FILE"
    tail -n 30 "$LOG_FILE" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ 3x-ui installed successfully." | tee -a "$LOG_FILE"

# Restart service
systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# Wait for config or DB
for i in {1..30}; do
    if [ -f "/usr/local/x-ui/bin/config.json" ] || [ -f "/usr/local/x-ui/db/x-ui.db" ]; then
        break
    fi
    sleep 2
done

# Gather credentials
CONFIG="/usr/local/x-ui/bin/config.json"
DB="/usr/local/x-ui/db/x-ui.db"
USERNAME="admin"
PASSWORD="admin123"
PORT="54321"
PATH_ID=""
IP=$(hostname -I | awk '{print $1}')

if [ -f "$CONFIG" ]; then
    USERNAME=$(jq -r '.webUser // "admin"' "$CONFIG" 2>/dev/null)
    PASSWORD=$(jq -r '.webPassword // "admin123"' "$CONFIG" 2>/dev/null)
    PORT=$(jq -r '.webPort // "54321"' "$CONFIG" 2>/dev/null)
    PATH_ID=$(jq -r '.webBasePath // ""' "$CONFIG" 2>/dev/null)
elif [ -f "$DB" ]; then
    USERNAME=$(sqlite3 "$DB" "SELECT username FROM users LIMIT 1;")
    PASSWORD=$(sqlite3 "$DB" "SELECT password FROM users LIMIT 1;")
fi

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
echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
