#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (with reliable MOTD console summary)
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
TEMP_CRED_FILE="/tmp/3xui_creds.txt"
RAW_CREDS_FILE="/etc/3xui_credentials.txt"
MOTD_SCRIPT="/etc/update-motd.d/99-3xui-creds"

set -e
export DEBIAN_FRONTEND=noninteractive

echo "========== $(date) Starting 3x-ui installation ==========" | tee "$LOG_FILE"

# --- 1. Robust Apt Update and Dependency Installation ---
dpkg --configure -a >/dev/null 2>&1 || true
echo "Running apt update..." | tee -a "$LOG_FILE"
apt-get update -y >/dev/null 2>&1 || true
echo "Installing required packages..." | tee -a "$LOG_FILE"
# Fixed: Replaced 'awk' with 'gawk' for Ubuntu 22.04 compatibility
apt-get install -y curl wget sudo tar lsof net-tools jq grep gawk
# Ensure core dependencies for MOTD are available (if not already installed)
apt-get install -y update-notifier-common || true 


# --- 2. Run 3x-ui official installer and capture credentials ---
echo "Downloading 3x-ui installer..." | tee -a "$LOG_FILE"
curl -fsSL -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh

echo "Running 3x-ui installation script..." | tee -a "$LOG_FILE"
# Use '() || true' to ignore non-zero exit code from installer, ensuring script continues
(
    bash /tmp/install_3xui.sh <<EOF 2>&1 | tee -a "$LOG_FILE" | grep -E 'Login:|Password:|URL:|Installation Complete!' > "$TEMP_CRED_FILE"
n
EOF
) || true


# --- 3. Parse credentials and set fallbacks ---
# Corrected parsing logic for URL and Credentials
USERNAME=$(grep 'Login:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r' || echo "admin")
PASSWORD=$(grep 'Password:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r' || echo "admin123")
FULL_URL_PART=$(grep 'URL:' "$TEMP_CRED_FILE" | awk '{print $2}' | tr -d '\r')

# Fallback for IP/Port/URL if capture failed
IP=$(hostname -I | awk '{print $1}')
PORT=$(grep -oP '"webPort":\s*\K\d+' /usr/local/x-ui/bin/config.json || echo "54321")
PATH_ID=$(grep -oP '"webBasePath":\s*"\K[^"]+' /usr/local/x-ui/bin/config.json || echo "")

# If URL parsing failed, construct it from config fallbacks
if [ -z "$FULL_URL_PART" ] || [ "$FULL_URL_PART" = "URL:" ]; then
    FULL_URL="http://$IP:$PORT/$PATH_ID"
else
    FULL_URL="$FULL_URL_PART"
fi

# Final safety net for credentials
if [ -z "$USERNAME" ] || [ "$USERNAME" = "null" ]; then USERNAME="admin"; fi
if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then PASSWORD="admin123"; fi


# --- 4. Implement Guaranteed MOTD Display ---
echo "Setting up guaranteed login summary (MOTD)..." | tee -a "$LOG_FILE"

# Create the final raw text file with color codes
cat <<EOF > "$RAW_CREDS_FILE"
\033[1;32m✅ 3x-ui Installation Complete!\033[0m
Login: $USERNAME
Password: $PASSWORD
URL: $FULL_URL
EOF

# Create the MOTD script to print the raw file on login
cat << 'EOF' > "$MOTD_SCRIPT"
#!/bin/sh
# This script runs via MOTD system (guaranteed execution on login)
CREDENTIALS_FILE="/etc/3xui_credentials.txt"

if [ -f "$CREDENTIALS_FILE" ]; then
    echo
    cat "$CREDENTIALS_FILE"
    echo
    # Remove the script and the raw file so it only shows up once
    rm -f "$CREDENTIALS_FILE" "$MOTAD_SCRIPT"
fi
EOF

# Make the MOTD script executable
chmod +x "$MOTD_SCRIPT"

echo "[DONE] $(date) Installation complete" | tee -a "$LOG_FILE"
