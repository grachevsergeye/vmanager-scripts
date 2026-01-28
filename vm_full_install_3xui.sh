#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (final; prints ONLY real creds)
# Enables HTTPS with self-signed certificate
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

# --- Grab official installer and run it, capturing output to LOG_FILE ---
echo "Downloading official 3x-ui installer..."
curl -fsSL -o "$INSTALLER_SH" "https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"
chmod +x "$INSTALLER_SH"

echo "Running official installer (its output will be captured in $LOG_FILE)..."
(bash "$INSTALLER_SH" <<'INP'
n
INP
) 2>&1 | tee -a "$LOG_FILE"

cp "$SSL_DIR/x-ui.crt" /usr/local/x-ui/x-ui.crt
cp "$SSL_DIR/x-ui.key" /usr/local/x-ui/x-ui.key

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Wait up to 120s for config or log lines to appear ---
echo "Waiting for config/log entries to appear..."
FOUND=0
for i in $(seq 1 60); do
  if [ -f "$CONFIG_FILE" ] || [ -f "$DB_FILE" ]; then
    FOUND=1
    break
  fi
  if grep -q -E 'Username:|Password:|Access URL:|Access URL|Generated random port|This is a fresh installation' "$LOG_FILE" 2>/dev/null; then
    FOUND=1
    break
  fi
  sleep 2
done

# --- Generate self-signed SSL cert ---
echo "Generating self-signed certificate for HTTPS..."
mkdir -p "$SSL_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SSL_DIR/x-ui.key" -out "$SSL_DIR/x-ui.crt" \
  -subj "/CN=$(hostname -I | awk '{print $1}')"

# --- Extract credentials: try config.json first (preferred) ---
USERNAME=""
PASSWORD=""
PORT=""
PATH_ID=""
URL=""

if [ -f "$CONFIG_FILE" ]; then
  echo "Parsing $CONFIG_FILE ..."
  USERNAME=$(jq -r '.webUser // empty' "$CONFIG_FILE" 2>/dev/null || true)
  PASSWORD=$(jq -r '.webPassword // empty' "$CONFIG_FILE" 2>/dev/null || true)
  PORT=$(jq -r '.webPort // empty' "$CONFIG_FILE" 2>/dev/null || true)
  PATH_ID=$(jq -r '.webBasePath // empty' "$CONFIG_FILE" 2>/dev/null || true)
fi

# --- If config didn't provide values, parse the installer log ---
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "Parsing installer log for Username/Password/URL..."
  GREP_USER=$(grep -m1 -E 'Username:' "$LOG_FILE" 2>/dev/null || true)
  GREP_PASS=$(grep -m1 -E 'Password:' "$LOG_FILE" 2>/dev/null || true)
  GREP_URL=$(grep -m1 -E 'Access URL:|Access URL|URL:|Access Url:' "$LOG_FILE" 2>/dev/null || true)

  [ -n "$GREP_USER" ] && USERNAME=$(echo "$GREP_USER" | sed -E 's/.*[Uu]sername: *//')
  [ -n "$GREP_PASS" ] && PASSWORD=$(echo "$GREP_PASS" | sed -E 's/.*[Pp]assword: *//')
  [ -n "$GREP_URL" ] && URL=$(echo "$GREP_URL" | sed -E 's/.*[Uu][Rr][Ll]: *//; s/.*Access URL: *//; s/^[[:space:]]*//')

  if [ -z "$URL" ]; then
    GREP_PORT=$(grep -m1 -E 'Port:' "$LOG_FILE" 2>/dev/null || true)
    GREP_PATH=$(grep -m1 -E 'WebBasePath:' "$LOG_FILE" 2>/dev/null || true)
    [ -n "$GREP_PORT" ] && PORT=$(echo "$GREP_PORT" | sed -E 's/.*Port: *//')
    [ -n "$GREP_PATH" ] && PATH_ID=$(echo "$GREP_PATH" | sed -E 's/.*WebBasePath: *//')
  fi
fi

# --- If still empty and DB exists, attempt sqlite query ---
if { [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; } && [ -f "$DB_FILE" ]; then
  echo "Trying sqlite DB extraction..."
  USERNAME_DB=$(sqlite3 "$DB_FILE" "SELECT username FROM user LIMIT 1;" 2>/dev/null || true)
  [ -n "$USERNAME_DB" ] && USERNAME="$USERNAME_DB"
fi

# --- Build final URL if not set ---
if [ -z "$URL" ] && [ -n "$PORT" ]; then
  IP=$(hostname -I | awk '{print $1}')
  URL="https://${IP}:$PORT"
  [ -n "$PATH_ID" ] && PATH_ID=$(echo "$PATH_ID" | sed 's#^/*##; s#/*$##') && URL="$URL/$PATH_ID"
fi

# --- Force HTTPS + credentials in 3x-ui ---
x-ui setting -username "$USERNAME"
x-ui setting -password "$PASSWORD"
x-ui setting -port "$PORT"
x-ui setting -listen 0.0.0.0
x-ui setting -tls true
x-ui setting -tls-cert "$SSL_DIR/x-ui.crt"
x-ui setting -tls-key "$SSL_DIR/x-ui.key"
systemctl restart x-ui
sleep 3

# --- Validate credentials ---
is_valid(){ local v="$1"; [ -n "$v" ] && [ "$v" != "null" ]; }
if ! is_valid "$USERNAME" || ! is_valid "$PASSWORD" || ! is_valid "$URL"; then
  echo "ERROR: Could not reliably extract real credentials."
  echo "Searched config: $CONFIG_FILE, db: $DB_FILE, log: $LOG_FILE"
  tail -n 40 "$LOG_FILE"
  exit 1
fi

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
echo ""
echo "⚠️ HTTPS uses a self-signed certificate. Browser may warn."
echo "=============================================="
echo ""
EOF
chmod +x "$SUMMARY_SCRIPT"
grep -q "bash $SUMMARY_SCRIPT" /root/.bashrc 2>/dev/null || echo "bash $SUMMARY_SCRIPT" >> /root/.bashrc

# --- Print immediately ---
bash "$SUMMARY_SCRIPT"
echo "[DONE] $(date) Installation finished, credentials printed above."
exit 0
