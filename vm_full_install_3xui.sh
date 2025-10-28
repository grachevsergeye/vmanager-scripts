#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (with persistent console summary) - FINAL REVISION
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.sh"
TEMP_CRED_FILE="/tmp/3xui_creds.txt"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# --- FIXED: Robust Apt Update and Dependency Installation ---
dpkg --configure -a >/dev/null 2>&1 || true

# Attempt apt update, allowing it to fail without halting the script (temporarily overriding 'set -e')
echo "Running apt update..."
apt-get update -y >/dev/null 2>&1 || true

# Install required packages. This command *must* succeed.
echo "Installing required packages..." | tee -a "$LOG_FILE"
apt-get install -y curl wget sudo tar lsof net-tools jq grep gawk

# --- END FIXED BLOCK ---


# Download and run 3x-ui official installer, capturing output
echo "Downloading 3x-ui installer..." | tee -a "$LOG_FILE"
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

# --- Run official installer and capture the output containing credentials ---
echo "Running 3x-ui installation script..." | tee -a "$LOG_FILE"
bash /tmp/install_3xui.sh <<EOF 2>&1 | tee -a "$LOG_FILE" | grep -E 'Login:|Password:|URL:|Installation Complete!' > "$TEMP_CRED_FILE"
n
EOF

# --- Parse credentials from the captured output file ---
USERNAME=$(grep 'Login:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r')
PASSWORD=$(grep 'Password:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r')
FULL_URL=$(grep 'URL:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r')

# Fallback: Get IP, Port, and Path from config if parsing failed or for completeness
if [ -z "$FULL_URL" ]; then
    echo "Warning: Failed to capture URL from installer output. Using config fallback." | tee -a "$LOG_FILE"
    
    # Wait until config.json appears
    for i in {1..30}; do
        if [ -f "/usr/local/x-ui/bin/config.json" ]; then break; fi
        sleep 2
    done

    PORT=$(jq -r '.webPort // "54321"' /usr/local/x-ui/bin/config.json)
    PATH_ID=$(jq -r '.webBasePath // ""' /usr/local/x-ui/bin/config.json)
    IP=$(hostname -I | awk '{print $1}')
    
    # Use config-derived URL if capture failed
    FULL_URL="http://$IP:$PORT/$PATH_ID"
fi

# Fallback for Username/Password if capture failed
if [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ]; then USERNAME="admin"; fi
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then PASSWORD="<<Check Logs/DB>>"; fi


# --- Save output file (3xui.sh) ---
cat <<EOF > "$SUMMARY_FILE"
#!/bin/bash
# Check if the summary has already been shown in this terminal session
if [ -z "\$3XUI_SHOWN" ]; then
    echo ""
    echo -e "\033[1;32m✅ 3x-ui Installation Complete!\033[0m"
    echo "Login: $USERNAME"
    echo "Password: $PASSWORD"
    echo "URL: $FULL_URL"
    echo ""
    export 3XUI_SHOWN=true
fi
EOF

chmod +x "$SUMMARY_FILE"

# --- Ensure summary shows at every login ---
if ! grep -q "bash $SUMMARY_FILE" /root/.bashrc; then
    echo "bash $SUMMARY_FILE" >> /root/.bashrc
fi

rm -f "$TEMP_CRED_FILE" # Clean up temp file
echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
