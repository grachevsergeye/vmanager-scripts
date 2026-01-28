#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (refactored)
# Installs 3x-ui, forces credentials, and prints only real creds
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_SCRIPT="/root/3xui.txt"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"
DB_FILE="/usr/local/x-ui/db/x-ui.db"
INSTALLER_SH="/tmp/install_3xui.sh"

set -e
export DEBIAN_FRONTEND=noninteractive

# --- Logging ---
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========== $(date) Starting 3x-ui installation =========="

# --- Prep & dependencies ---
dpkg --configure -a 2>/dev/null || true
apt-get update -y >/dev/null 2>&1
apt-get install -y curl wget sudo tar lsof net-tools jq sqlite3 iproute2 >/dev/null 2>&1 || true

# --- Download official installer ---
echo "Downloading official 3x-ui installer..."
curl -fsSL -o "$INSTALLER_SH" "https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"
chmod +x "$INSTALLER_SH"

# --- Run official installer ---
echo "Running official installer..."
( bash "$INSTALLER_SH" <<'INP'
n
INP
) 2>&1 | tee -a "$LOG_FILE"

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Force credentials ---
echo "Forcing custom credentials..."
ADMIN_USER="admin"
ADMIN_PASS="$(openssl rand -base64 14)"
PORT="54321"

x-ui setting -username "$ADMIN_USER" -password "$ADMIN_PASS"
x-ui setting -port "$PORT"
x-ui setting -listen 0.0.0.0
systemctl restart x-ui
sleep 3

IP=$(hostname -I | awk '{print $1}')
URL="http://${IP}:${PORT}"

# --- Summary script ---
cat > "$SUMMARY_SCRIPT" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo "✅ 3x-ui Installation Complete!"
echo ""
echo "Login: $ADMIN_USER"
echo "Password: $ADMIN_PASS"
echo "URL: $URL"
echo "=============================================="
echo ""
EOF
chmod +x "$SUMMARY_SCRIPT"

# add to root bashrc for convenience
if ! grep -q "bash $SUMMARY_SCRIPT" /root/.bashrc 2>/dev/null; then
  echo "bash $SUMMARY_SCRIPT" >> /root/.bashrc
fi

# --- Print credentials immediately ---
bash "$SUMMARY_SCRIPT"

# --- Optional: Try to extract existing credentials from config/db (fallback) ---
USERNAME=$(jq -r '.webUser // empty' "$CONFIG_FILE" 2>/dev/null || true)
PASSWORD=$(jq -r '.webPassword // empty' "$CONFIG_FILE" 2>/dev/null || true)
PORT_CFG=$(jq -r '.webPort // empty' "$CONFIG_FILE" 2>/dev/null || true)
PATH_ID=$(jq -r '.webBasePath // empty' "$CONFIG_FILE" 2>/dev/null || true)
if { [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; } && [ -f "$DB_FILE" ]; then
  USERNAME_DB=$(sqlite3 "$DB_FILE" "SELECT username FROM user LIMIT 1;" 2>/dev/null || true)
  [ -n "$USERNAME_DB" ] && USERNAME="$USERNAME_DB"
fi

# --- Construct fallback URL if needed ---
if [ -z "$URL" ] && [ -n "$PORT_CFG" ]; then
  IP=$(hostname -I | awk '{print $1}')
  URL="http://$IP:$PORT_CFG"
  [ -n "$PATH_ID" ] && URL="$URL/$PATH_ID"
fi

# --- Validate extracted creds ---
is_valid() { [ -n "$1" ] && [ "$1" != "null" ]; }

if ! is_valid "$USERNAME" || ! is_valid "$PASSWORD" || ! is_valid "$URL"; then
  echo "[WARN] Could not extract alternative credentials. Forced ones are used."
fi

echo "[DONE] $(date) Installation finished, credentials printed above."
exit 0
