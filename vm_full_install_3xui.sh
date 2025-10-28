#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (FINAL: Service & Credential Guarantee)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
TEMP_CRED_FILE="/tmp/3xui_creds.txt"
RAW_CREDS_FILE="/etc/3xui_credentials.txt"
MOTD_SCRIPT="/etc/update-motd.d/99-3xui-creds"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# --- 1. Dependencies (same as before) ---
dpkg --configure -a >/dev/null 2>&1 || true
echo "Running apt update..." | tee -a "$LOG_FILE"
apt-get update -y >/dev/null 2>&1 || true
echo "Installing required packages..." | tee -a "$LOG_FILE"
apt-get install -y curl wget sudo tar lsof net-tools jq grep gawk update-notifier-common

# --- 2. Run 3x-ui official installer (same as before) ---
echo "Downloading and running 3x-ui installer..." | tee -a "$LOG_FILE"
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh
(bash /tmp/install_3xui.sh <<EOF 2>&1 | tee -a "$LOG_FILE" | grep -E 'Login:|Password:|URL:|Installation Complete!' > "$TEMP_CRED_FILE"
n
EOF
) || true


# --- 3. GUARANTEE CREDENTIALS AND SERVICE RESTART ---
GUARANTEED_PASSWORD="Vmanger6-UserPassword" # This is the known, expected password
GUARANTEED_USERNAME="admin"

echo "Forcing guaranteed credentials and restarting service..." | tee -a "$LOG_FILE"

if command -v x-ui &> /dev/null; then
    # Set known password
    echo "y" | x-ui setting -username "$GUARANTEED_USERNAME" -password "$GUARANTEED_PASSWORD"

    # --- CRITICAL: Ensure service is running and loads the new config ---
    systemctl daemon-reload
    systemctl enable x-ui || true
    systemctl restart x-ui
    sleep 5 # Wait for restart
    systemctl status x-ui | grep "Active:" | tee -a "$LOG_FILE"
else
    echo "CRITICAL: x-ui CLI not found, cannot guarantee password." | tee -a "$LOG_FILE"
fi

# --- 4. Final Credential Construction for Display ---
USERNAME="$GUARANTEED_USERNAME"
PASSWORD="$GUARANTEED_PASSWORD"

# Use config file for IP/Port, or fall back to known defaults
IP=$(hostname -I | awk '{print $1}')
PORT=$(jq -r '.webPort // "54321"' "$CONFIG_FILE" 2>/dev/null || echo "54321")
PATH_ID=$(jq -r '.webBasePath // ""' "$CONFIG_FILE" 2>/dev/null || echo "")

# Final URL display
FULL_URL="http://$IP:$PORT/$PATH_ID"

# --- 5. Implement Guaranteed MOTD Display (same as before) ---
echo "Setting up guaranteed login summary (MOTD)..." | tee -a "$LOG_FILE"

# Create the final raw text file
cat <<EOF > "$RAW_CREDS_FILE"
\033[1;32m✅ 3x-ui Installation Complete!\033[0m
Login: $USERNAME
Password: $PASSWORD
URL: $FULL_URL
EOF

# Create the MOTD script
cat << 'EOF' > "$MOTD_SCRIPT"
#!/bin/sh
# This script runs via MOTD system (guaranteed execution on login)
CREDENTIALS_FILE="/etc/3xui_credentials.txt"

if [ -f "$CREDENTIALS_FILE" ]; then
    echo
    cat "$CREDENTIALS_FILE"
    echo
    # Remove the script and the raw file so it only shows up once
    rm -f "$CREDENTIALS_FILE" "$MOTD_SCRIPT"
fi
EOF

# Make the MOTD script executable
chmod +x "$MOTD_SCRIPT"

echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
