#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (final; prints ONLY real creds)
# Automatically handles HTTPS with self-signed certificate
# Falls back to HTTP if TLS isn’t working
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_SCRIPT="/root/3xui.txt"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"
DB_FILE="/usr/local/x-ui/db/x-ui.db"
INSTALLER_SH="/tmp/install_3xui.sh"
SSL_DIR="/usr/local/x-ui/ssl"

set -e
export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========== $(date) Starting 3x-ui installation =========="

# --- Prep & deps ---
dpkg --configure -a 2>/dev/null || true
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl wget sudo tar lsof net-tools jq sqlite3 iproute2 openssl >/dev/null 2>&1 || true

# --- Grab official installer and run it ---
echo "Downloading official 3x-ui installer..."
curl -fsSL -o "$INSTALLER_SH" "https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"
chmod +x "$INSTALLER_SH"

echo "Running official installer..."
(bash "$INSTALLER_SH" <<'INP'
n
INP
) 2>&1 | tee -a "$LOG_FILE"

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Wait for config.json to exist and contain webPort ---
echo "Waiting for config.json to contain webPort..."
TRIES=0
while [ ! -f "$CONFIG_FILE" ] || [ -z "$(jq -r '.webPort // empty' "$CONFIG_FILE" 2>/dev/null)" ]; do
    sleep 2
    TRIES=$((TRIES + 1))
    if [ $TRIES -gt 60 ]; then
        echo "ERROR: config.json not ready after 2 minutes."
        tail -n 40 "$LOG_FILE"
        exit 1
    fi
done

# --- Extract credentials & port ---
USERNAME=$(jq -r '.webUser // empty' "$CONFIG_FILE")
PASSWORD=$(jq -r '.webPassword // empty' "$CONFIG_FILE")
PORT=$(jq -r '.webPort // empty' "$CONFIG_FILE")
PATH_ID=$(jq -r '.webBasePath // empty' "$CONFIG_FILE")

# Fallback: sqlite DB for username
if [ -z "$USERNAME" ] && [ -f "$DB_FILE" ]; then
    USERNAME=$(sqlite3 "$DB_FILE" "SELECT username FROM user LIMIT 1;" 2>/dev/null || true)
fi

# --- Force credentials in x-ui ---
x-ui setting -username "$USERNAME"
x-ui setting -password "$PASSWORD"
x-ui setting -port "$PORT"
x-ui setting -listen 0.0.0.0
systemctl restart x-ui
sleep 3

# --- Generate self-signed SSL cert ---
mkdir -p "$SSL_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/x-ui.key" -out "$SSL_DIR/x-ui.crt" \
  -subj "/CN=$(hostname -I | awk '{print $1}')"
chmod 600 "$SSL_DIR/x-ui.key" "$SSL_DIR/x-ui.crt"
chown root:root "$SSL_DIR/x-ui.key" "$SSL_DIR/x-ui.crt"

# --- Enable TLS if supported ---
TLS_OK=0
if x-ui setting -tls true >/dev/null 2>&1; then
    x-ui setting -tls-cert "$SSL_DIR/x-ui.crt"
    x-ui setting -tls-key "$SSL_DIR/x-ui.key"
    systemctl restart x-ui
    sleep 3
    if curl -k --max-time 5 "https://127.0.0.1:$PORT" >/dev/null 2>&1; then
        TLS_OK=1
    fi
fi

# --- Build final URL ---
IP=$(hostname -I | awk '{print $1}')
URL="http://$IP:$PORT"
[ "$TLS_OK" -eq 1 ] && URL="https://$IP:$PORT"
[ -n "$PATH_ID" ] && PATH_ID=$(echo "$PATH_ID" | sed 's#^/*##; s#/*$##') && URL="$URL/$PATH_ID"

# --- Write summary script ---
cat > "$SUMMARY_SCRIPT" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo "✅ 3x-ui Installation Complete!"
echo ""
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: $URL"
EOF

if [ "$TLS_OK" -eq 1 ]; then
cat >> "$SUMMARY_SCRIPT" <<EOF
echo ""
echo "⚠️ HTTPS uses a self-signed certificate. Browser may warn."
EOF
else
cat >> "$SUMMARY_SCRIPT" <<EOF
echo ""
echo "⚠️ Using HTTP because HTTPS is not supported on this version/port."
EOF
fi

cat >> "$SUMMARY_SCRIPT" <<EOF
echo "=============================================="
echo ""
EOF

chmod +x "$SUMMARY_SCRIPT"
grep -q "bash $SUMMARY_SCRIPT" /root/.bashrc 2>/dev/null || echo "bash $SUMMARY_SCRIPT" >> /root/.bashrc

# --- Print immediately ---
bash "$SUMMARY_SCRIPT"
echo "[DONE] $(date) Installation finished, credentials printed above."
exit 0
