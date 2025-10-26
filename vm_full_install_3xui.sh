#!/bin/bash
LOG_FILE="/var/log/vm_install_3xui.log"
SUMMARY_FILE="/root/3xui.txt"

exec > >(tee -a "$LOG_FILE") 2>&1
set -e

error_exit() {
  echo "❌ ERROR: $1" | tee "$SUMMARY_FILE"
  exit 1
}

echo "=== Installing 3x-ui $(date) ==="

apt-get update -y || error_exit "apt update failed"
apt-get install -y curl wget sudo jq || error_exit "deps failed"

# Fix missing systemctl wrappers on minimal Ubuntu
if ! command -v systemctl >/dev/null 2>&1; then
  echo "Creating systemctl fallback..."
  cat >/usr/bin/systemctl <<'EOF'
#!/bin/bash
if [ "$1" = "enable" ] || [ "$1" = "start" ]; then
  service "$2" start
else
  service "$2" "$1"
fi
EOF
  chmod +x /usr/bin/systemctl
fi

# Run 3x-ui installer
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) || error_exit "3x-ui install failed"

sleep 5

# Attempt to detect credentials
CFG="/etc/x-ui/x-ui.db"
IP=$(hostname -I | awk '{print $1}')
PORT=$(ss -tlnp 2>/dev/null | awk '/x-ui/ {print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | head -n1)
USER=$(grep -m1 -Eo 'Username: *[^ ]+' "$LOG_FILE" | awk '{print $2}')
PASS=$(grep -m1 -Eo 'Password: *[^ ]+' "$LOG_FILE" | awk '{print $2}')

cat <<EOF > "$SUMMARY_FILE"
✅ 3x-ui installed successfully!
Panel: http://${IP}:${PORT:-54321}
Username: ${USER:-admin}
Password: ${PASS:-admin}
EOF

echo "Summary saved to $SUMMARY_FILE"
