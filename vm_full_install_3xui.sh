#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (with persistent console summary)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# Fix apt issues and install deps
dpkg --configure -a >/dev/null 2>&1 || true
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget sudo tar lsof net-tools jq >/dev/null 2>&1

# Download and run 3x-ui official installer
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

bash /tmp/install_3xui.sh <<EOF | tee -a "$LOG_FILE"
n
EOF

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Wait until config.json appears ---
for i in {1..30}; do
    if [ -f "$CONFIG_FILE" ]; then
        break
    fi
    echo "Waiting for config.json... ($i)"
    sleep 2
done

# --- Parse credentials safely ---
USERNAME=$(jq -r '.webUser // .username // .admin // empty' "$CONFIG_FILE" 2>/dev/null)
PASSWORD=$(jq -r '.webPassword // .password // .pass // empty' "$CONFIG_FILE" 2>/dev/null)
PORT=$(jq -r '.webPort // .port // empty' "$CONFIG_FILE" 2>/dev/null)
PATH_ID=$(jq -r '.webBasePath // .path // empty' "$CONFIG_FILE" 2>/dev/null)

# --- Fallback if still empty ---
if [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ]; then USERNAME="admin"; fi
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then PASSWORD="admin123"; fi
if [ -z "$PORT" ] || [ "$PORT" = "null" ]; then PORT="54321"; fi
if [ -z "$PATH_ID" ] || [ "$PATH_ID" = "null" ]; then PATH_ID=""; fi

IP=$(hostname -I | awk '{print $1}')

# --- Save output file ---
cat <<EOF > "$SUMMARY_FILE"
echo ""
echo -e "\033[1;32m✅ 3x-ui Installation Complete!\033[0m"
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: http://$IP:$PORT/$PATH_ID"
echo ""
EOF

chmod +x "$SUMMARY_FILE"

# --- Ensure summary shows at every login ---
if ! grep -q "bash /root/3xui.txt" /root/.bashrc; then
    echo "bash /root/3xui.txt" >> /root/.bashrc
fi

echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
