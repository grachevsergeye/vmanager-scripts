#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (final version with credential summary)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"
DB_FILE="/usr/local/x-ui/db/x-ui.db"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# Fix apt and install dependencies
dpkg --configure -a >/dev/null 2>&1 || true
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget sudo tar lsof net-tools jq sqlite3 iproute2 >/dev/null 2>&1

# Download and run official installer
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

bash /tmp/install_3xui.sh <<EOF | tee -a "$LOG_FILE"
n
EOF

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Wait up to 90s for config or DB to appear ---
for i in {1..45}; do
    if [ -f "$CONFIG_FILE" ] || [ -f "$DB_FILE" ]; then
        break
    fi
    echo "Waiting for 3x-ui configuration... ($i)" | tee -a "$LOG_FILE"
    sleep 2
done

# --- Extract credentials ---
USERNAME="admin"
PASSWORD="admin123"
PORT="54321"
PATH_ID=""
IP=$(hostname -I | awk '{print $1}')

if [ -f "$CONFIG_FILE" ]; then
    USERNAME=$(jq -r '.webUser // "admin"' "$CONFIG_FILE" 2>/dev/null)
    PASSWORD=$(jq -r '.webPassword // "admin123"' "$CONFIG_FILE" 2>/dev/null)
    PORT=$(jq -r '.webPort // "54321"' "$CONFIG_FILE" 2>/dev/null)
    PATH_ID=$(jq -r '.webBasePath // ""' "$CONFIG_FILE" 2>/dev/null)
elif [ -f "$DB_FILE" ]; then
    USERNAME=$(sqlite3 "$DB_FILE" "SELECT username FROM users LIMIT 1;")
    PASSWORD=$(sqlite3 "$DB_FILE" "SELECT password FROM users LIMIT 1;")
fi

# --- Save summary file ---
cat <<EOF > "$SUMMARY_FILE"
echo ""
echo -e "\033[1;32m✅ 3x-ui Installation Complete!\033[0m"
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: http://$IP:$PORT/$PATH_ID"
echo ""
EOF

chmod +x "$SUMMARY_FILE"

# --- Auto-display summary on login ---
if ! grep -q "bash /root/3xui.txt" /root/.bashrc; then
    echo "bash /root/3xui.txt" >> /root/.bashrc
fi

echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
bash "$SUMMARY_FILE"
