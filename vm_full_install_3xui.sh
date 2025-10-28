#!/bin/bash
# ==========================================================
# 3x-ui Full Installer with Real-Time Summary Output (for VManager)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"
exec > >(tee -a "$LOG_FILE") 2>&1
set -e

echo "========== $(date) Starting 3x-ui installation =========="

export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget sudo tar lsof net-tools cron jq

# --- Download and install 3x-ui ---
curl -L -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh
bash /tmp/install_3xui.sh <<EOF
n
EOF

systemctl enable x-ui || true
systemctl restart x-ui || true

# --- Extract the real credentials from logs ---
sleep 3
USERNAME=$(grep -m1 'Username:' "$LOG_FILE" | awk '{print $2}')
PASSWORD=$(grep -m1 'Password:' "$LOG_FILE" | awk '{print $2}')
PORT=$(grep -m1 'Port:' "$LOG_FILE" | awk '{print $2}')
PATH_ID=$(grep -m1 'WebBasePath:' "$LOG_FILE" | awk '{print $2}')
IP=$(hostname -I | awk '{print $1}')

# --- Handle fallback if parsing failed ---
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$PORT" ] || [ -z "$PATH_ID" ]; then
  echo "⚠️ Warning: Unable to detect credentials automatically. Check $LOG_FILE."
  exit 1
fi

# --- Save to summary file ---
cat <<EOF > "$SUMMARY_FILE"
✅ Installation complete!
Login: $USERNAME
Password: $PASSWORD
URL: http://$IP:$PORT/$PATH_ID
EOF

# --- Print final message clearly ---
echo
echo "==============================================="
cat "$SUMMARY_FILE"
echo "==============================================="
echo "Logs: $LOG_FILE"
echo "[DONE] $(date) 3x-ui installation complete."
