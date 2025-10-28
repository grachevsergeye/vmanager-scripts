#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (Silent Installation, MOTD Summary)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
TEMP_CRED_FILE="/tmp/3xui_creds.txt"
RAW_CREDS_FILE="/etc/3xui_credentials.txt"
MOTD_SCRIPT="/etc/update-motd.d/99-3xui-creds"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# --- 1. Dependencies (Silent Install) ---
dpkg --configure -a >/dev/null 2>&1 || true
echo "Running apt update..." | tee -a "$LOG_FILE"
# Send apt-get output to log, hide from terminal
apt-get update -y >/dev/null 2>&1 || true
echo "Installing required packages..." | tee -a "$LOG_FILE"
apt-get install -y curl wget sudo tar lsof net-tools jq grep gawk update-notifier-common >/dev/null 2>&1


# --- 2. Run 3x-ui official installer and capture credentials ---
echo "Downloading and running 3x-ui installer (output suppressed)..." | tee -a "$LOG_FILE"
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

# CRITICAL: Run installer, redirect ALL verbose output to log, and only CAPTURE the final summary block
INSTALLER_OUTPUT=$(
    bash /tmp/install_3xui.sh <<EOF 2>&1 | tee -a "$LOG_FILE" # Output goes to log, but is also captured
n
EOF
) || true

# Extract the final summary block from the captured output
echo "$INSTALLER_OUTPUT" | awk '/^===============================================/,/^===============================================/ {print}' > "$TEMP_CRED_FILE"


# --- 3. Parse and set fallbacks (Use the successful random values) ---
USERNAME=$(grep 'Login:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r' || echo "admin")
PASSWORD=$(grep 'Password:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r' || echo "CHECK_LOGS")
FULL_URL=$(grep 'URL:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r' || echo "http://FAIL")

# If final URL parsing fails, fall back to robust config check (safety net)
if [[ "$FULL_URL" == "http://FAIL" ]]; then
    IP=$(hostname -I | awk '{print $1}')
    PORT=$(jq -r '.webPort // "54321"' "$CONFIG_FILE" 2>/dev/null || echo "54321")
    PATH_ID=$(jq -r '.webBasePath // ""' "$CONFIG_FILE" 2>/dev/null || echo "")
    FULL_URL="http://$IP:$PORT/$PATH_ID"
fi

# --- 4. Implement Guaranteed MOTD Display (using the captured random credentials) ---
echo "Setting up guaranteed login summary (MOTD)..." | tee -a "$LOG_FILE"

# Create the final raw text file with the captured random credentials
cat <<EOF > "$RAW_CREDS_FILE"
\033[1;32m✅ Installation complete!\033[0m
Login: $USERNAME
Password: $PASSWORD
URL: $FULL_URL
EOF

# Create the MOTD script (to run once and delete itself)
cat << 'EOF' > "$MOTD_SCRIPT"
#!/bin/sh
CREDENTIALS_FILE="/etc/3xui_credentials.txt"

if [ -f "$CREDENTIALS_FILE" ]; then
    echo
    cat "$CREDENTIALS_FILE"
    echo
    # Remove the output file and the script so it only shows up on the first login
    rm -f "$CREDENTIALS_FILE" "$MOTD_SCRIPT"
fi
EOF

# Make the MOTD script executable
chmod +x "$MOTD_SCRIPT"

echo "[DONE] $(date) Installation complete. Check /var/log/vm_install_3xui.log for full output." | tee -a "$LOG_FILE"
