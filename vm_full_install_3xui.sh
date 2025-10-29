#!/bin/bash
# ==========================================================
# 3x-ui Full Installer (final; prints ONLY real creds)
# Place this at:
# https://raw.githubusercontent.com/grachevsergeye/vmanager-scripts/refs/heads/main/vm_full_install_3xui.sh
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_SCRIPT="/root/3xui.txt"
CONFIG_FILE="/usr/local/x-ui/bin/config.json"
DB_FILE="/usr/local/x-ui/db/x-ui.db"
INSTALLER_SH="/tmp/install_3xui.sh"

set -e
export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========== $(date) Starting 3x-ui installation =========="

# --- Prep & deps ---
dpkg --configure -a 2>/dev/null || true
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y curl wget sudo tar lsof net-tools jq sqlite3 iproute2 >/dev/null 2>&1 || true

# --- Grab official installer and run it, capturing output to LOG_FILE ---
echo "Downloading official 3x-ui installer..."
curl -fsSL -o "$INSTALLER_SH" "https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"
chmod +x "$INSTALLER_SH"

echo "Running official installer (its output will be captured in $LOG_FILE)..."
# run installer and tee output to log (installer may prompt; we send 'n' as used previously)
( bash "$INSTALLER_SH" <<'INP'
n
INP
) 2>&1 | tee -a "$LOG_FILE"

systemctl enable x-ui >/dev/null 2>&1 || true
systemctl restart x-ui >/dev/null 2>&1 || true

# --- Wait up to 120s for config or log lines to appear ---
echo "Waiting for config/log entries to appear..."
FOUND=0
for i in $(seq 1 60); do
  # check config file or db or installer log lines that indicate generated creds
  if [ -f "$CONFIG_FILE" ] || [ -f "$DB_FILE" ]; then
    FOUND=1
    break
  fi
  # also check log for obvious installer output
  if grep -q -E 'Username:|Password:|Access URL:|Access URL|Generated random port|This is a fresh installation' "$LOG_FILE" 2>/dev/null; then
    FOUND=1
    break
  fi
  sleep 2
done

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

# --- If config didn't provide values, parse the installer log for explicit printed credentials ---
if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  # Many installers print lines like:
  # Username: rUdhoh4D1J
  # Password: 3ak1kzvThS
  # Access URL: http://1.2.3.4:59132/abcd
  # or separate Port:/WebBasePath: lines
  echo "Parsing installer log for Username/Password/URL..."
  GREP_USER=$(grep -m1 -E 'Username:' "$LOG_FILE" 2>/dev/null || true)
  GREP_PASS=$(grep -m1 -E 'Password:' "$LOG_FILE" 2>/dev/null || true)
  GREP_URL=$(grep -m1 -E 'Access URL:|Access URL|URL:|Access Url:' "$LOG_FILE" 2>/dev/null || true)

  if [ -n "$GREP_USER" ]; then
    USERNAME=$(echo "$GREP_USER" | sed -E 's/.*[Uu]sername: *//')
  fi
  if [ -n "$GREP_PASS" ]; then
    PASSWORD=$(echo "$GREP_PASS" | sed -E 's/.*[Pp]assword: *//')
  fi
  if [ -n "$GREP_URL" ]; then
    URL=$(echo "$GREP_URL" | sed -E 's/.*[Uu][Rr][Ll]: *//; s/.*Access URL: *//; s/^[[:space:]]*//')
  fi

  # If no Access URL, try to reconstruct from IP/Port/WebBasePath in log
  if [ -z "$URL" ]; then
    # try Port:
    GREP_PORT=$(grep -m1 -E 'Port:' "$LOG_FILE" 2>/dev/null || true)
    GREP_PATH=$(grep -m1 -E 'WebBasePath:' "$LOG_FILE" 2>/dev/null || true)
    if [ -n "$GREP_PORT" ]; then
      PORT=$(echo "$GREP_PORT" | sed -E 's/.*Port: *//')
    fi
    if [ -n "$GREP_PATH" ]; then
      PATH_ID=$(echo "$GREP_PATH" | sed -E 's/.*WebBasePath: *//')
    fi
  fi
fi

# --- If still empty and DB exists, attempt sqlite query (note: DB may store hashed pass) ---
if { [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; } && [ -f "$DB_FILE" ]; then
  echo "Trying sqlite DB extraction..."
  # these queries depend on the DB schema; password may be hashed — installer typically prints plaintext to log.
  USERNAME_DB=$(sqlite3 "$DB_FILE" "SELECT username FROM user LIMIT 1;" 2>/dev/null || true)
  if [ -n "$USERNAME_DB" ]; then
    USERNAME="$USERNAME_DB"
  fi
fi

# --- Build final URL if we have components and not full URL ---
if [ -z "$URL" ] && [ -n "$PORT" ]; then
  IP=$(hostname -I | awk '{print $1}')
  URL="http://$IP:$PORT"
  if [ -n "$PATH_ID" ]; then
    # trim leading/trailing slashes
    PATH_ID=$(echo "$PATH_ID" | sed 's#^/*##; s#/*$##')
    URL="$URL/$PATH_ID"
  fi
fi

# --- Validate: we will NOT show fake defaults; require real-looking values ---
is_valid() {
  local v="$1"
  [ -n "$v" ] && [ "$v" != "null" ]
}

if ! is_valid "$USERNAME" || ! is_valid "$PASSWORD" || ! is_valid "$URL"; then
  echo "ERROR: Could not reliably extract real credentials for 3x-ui."
  echo "Searched:"
  echo " - config: $CONFIG_FILE (exists: $([ -f "$CONFIG_FILE" ] && echo yes || echo no))"
  echo " - db: $DB_FILE (exists: $([ -f "$DB_FILE" ] && echo yes || echo no))"
  echo " - installer log: $LOG_FILE (last lines):"
  tail -n 40 "$LOG_FILE"
  echo ""
  echo "Please check the log or run the installer manually to inspect output."
  exit 1
fi

# --- Write the summary script (plain text output) ---
cat > "$SUMMARY_SCRIPT" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo "✅ 3x-ui Installation Complete!"
echo ""
echo "Login: $USERNAME"
echo "Password: $PASSWORD"
echo "URL: $URL"
echo "=============================================="
echo ""
EOF
chmod +x "$SUMMARY_SCRIPT"

# add to root bashrc so it's shown on new shell
if ! grep -q "bash $SUMMARY_SCRIPT" /root/.bashrc 2>/dev/null; then
  echo "bash $SUMMARY_SCRIPT" >> /root/.bashrc
fi

# Print right now to active console
bash "$SUMMARY_SCRIPT"

echo "[DONE] $(date) Installation finished, credentials printed above."
exit 0
