#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (with auto console summary for VManager)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# --- Fix any apt issues ---
dpkg --configure -a >/dev/null 2>&1 || true
apt --fix-broken install -y >/dev/null 2>&1 || true
apt update -y >/dev/null 2>&1
apt install -y curl wget sudo tar lsof net-tools cron jq >/dev/null 2>&1

# --- Download and run 3x-ui installer ---
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh
bash /tmp/install_3xui.sh <<EOF | tee -a "$LOG_FILE"
n
EOF

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Wait for service initialization ---
sleep 3

# --- Extract credentials from log or default output ---
USERNAME=$(grep -m1 'Username:' "$LOG_FILE" | awk '{print $2}')
PASSWORD=$(grep -m1 'Password:' "$LOG_FILE" | awk '{print $2}')
PORT=$(grep -m1 'Port:' "$LOG_FILE" | awk '{print $2}')
PATH_ID=$(grep -m1 'WebBasePath:' "$LOG_FILE" | awk '{print $2}')
IP=$(hostname -I | awk '{print $1}')

# --- Fallback detection if parsing failed ---
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PORT" ] || [ -z "$PATH_ID" ]; then
    echo "⚠️ Could not auto-detect credentials, check $LOG_FILE"
    exit 1
fi

# --- Create summary display file ---
cat <<EOF > "$SUMMARY_FILE"
echo -e "\033[1;32m✅ Installation complete!\033[0m"
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: http://$IP:$PORT/$PATH_ID"
EOF

chmod +x "$SUMMARY_FILE"

# --- Show on every future login ---
if ! grep -q "3xui.txt" /root/.bashrc; then
  echo "bash /root/3xui.txt" >> /root/.bashrc
fi

echo "[DONE] $(date) 3x-ui installation complete." | tee -a "$LOG_FILE"
