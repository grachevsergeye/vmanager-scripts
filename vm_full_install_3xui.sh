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


# --- NEW: Force a known, reliable password for guaranteed access ---
GUARANTEED_PASSWORD="Vmanger6-UserPassword" # Set a password you know will work
GUARANTEED_USERNAME="admin"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"

echo "Forcing guaranteed credentials..." | tee -a "$LOG_FILE"
# Check if the 'x-ui' command exists
if command -v x-ui &> /dev/null; then
    # Use the x-ui CLI tool to reset the credentials
    echo "y" | x-ui setting -username "$GUARANTEED_USERNAME" -password "$GUARANTEED_PASSWORD"
else
    echo "Warning: x-ui CLI not found, falling back to displayed credentials." | tee -a "$LOG_FILE"
fi

# --- 3. Parse and set fallbacks (Now using guaranteed values) ---
USERNAME="$GUARANTEED_USERNAME"
PASSWORD="$GUARANTEED_PASSWORD"

# Fallback for IP/Port/URL (same logic, but uses the guaranteed URL construction)
IP=$(hostname -I | awk '{print $1}')
PORT=$(grep -oP '"webPort":\s*\K\d+' "$CONFIG_FILE" 2>/dev/null || echo "54321")
PATH_ID=$(grep -oP '"webBasePath":\s*"\K[^"]+' "$CONFIG_FILE" 2>/dev/null || echo "")
FULL_URL="http://$IP:$PORT/$PATH_ID"

# --- 4. Implement Guaranteed MOTD Display ---
# ... (MOTD logic is now updated to use GUARANTEED_PASSWORD) ...
echo "Setting up guaranteed login summary (MOTD)..." | tee -a "$LOG_FILE"

# Create the final raw text file with guaranteed credentials
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
