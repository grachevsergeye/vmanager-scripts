#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (with persistent console summary)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# --- Fix apt issues and install deps ---
dpkg --configure -a >/dev/null 2>&1 || true
apt --fix-broken install -y >/dev/null 2>&1 || true
apt update -y >/dev/null 2>&1
apt install -y curl wget sudo tar lsof net-tools jq >/dev/null 2>&1

# --- Download and install 3x-ui ---
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

# run installer silently
bash /tmp/install_3xui.sh <<EOF | tee -a "$LOG_FILE"
n
EOF

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Extract values ---
sleep 2
USERNAME=$(grep -m1 'Username:' "$LOG_FILE" | awk '{print $2}')
PASSWORD=$(grep -m1 'Password:' "$LOG_FILE" | awk '{print $2}')
PORT=$(grep -m1 'Port:' "$LOG_FILE" | awk '{print $2}')
PATH_ID=$(grep -m1 'WebBasePath:' "$LOG_FILE" | awk '{print $2}')
IP=$(hostname -I | awk '{print $1}')

# --- If no credentials found, fallback ---
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PORT" ] || [ -z "$PATH_ID" ]; then
    echo "⚠️ Could not parse credentials, check $LOG_FILE"
    exit 0
fi

# --- Create summary output script ---
cat <<EOF > "$SUMMARY_FILE"
echo ""
echo -e "\033[1;32m✅ 3x-ui Installation Complete!\033[0m"
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: http://$IP:$PORT/$PATH_ID"
echo ""
EOF
chmod +x "$SUMMARY_FILE"

# --- Ensure it runs at every login ---
if ! grep -q "bash /root/3xui.txt" /root/.bashrc; then
  echo "bash /root/3xui.txt" >> /root/.bashrc
fi

echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"

