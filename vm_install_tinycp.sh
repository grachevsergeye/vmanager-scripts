#!/bin/bash
# ==========================================================
# TinyCP Full Installer (shows real credentials at login)
# ==========================================================

LOG="/var/log/vm_install_tinycp.log"
SUMMARY="/root/tinycp.txt"
TINY_DIR="/root/.tinycp"

exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) TinyCP installer started ==="

# Fix & deps
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y wget curl sudo lsb-release || true

# Run official TinyCP installer and capture *all* output
echo "[*] Running official TinyCP installer..."
bash <(wget -qO- https://tinycp.com/install.sh) | tee -a "$LOG" || true

# Give it a moment to finish setup
sleep 5

# Detect password (TinyCP usually stores it under /root/.tinycp or shows it during install)
PASS=""
if [ -f "$TINY_DIR/password" ]; then
  PASS=$(cat "$TINY_DIR/password" 2>/dev/null | head -n1)
fi

# If not found, fallback to parsing the log
if [ -z "$PASS" ]; then
  PASS=$(grep -Eo 'Password: [^[:space:]]+' "$LOG" | tail -n1 | awk '{print $2}')
fi

[ -z "$PASS" ] && PASS="(not found - check $LOG)"

IP=$(hostname -I | awk '{print $1}')
DATE="$(date)"

# Create summary script
cat > "$SUMMARY" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo -e "\033[1;32m✅ TinyCP Installation Complete!\033[0m"
echo ""
echo "Date: $DATE"
echo ""
echo "Panel: http://${IP}:8080"
echo "Login: admin"
echo "Password: $PASS"
echo "=============================================="
echo ""
EOF

chmod +x "$SUMMARY"

# Show it on login
BASHRC="/root/.bashrc"
if ! grep -qF "bash /root/tinycp.txt" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# show TinyCP credentials at login" >> "$BASHRC"
  echo "if [ -f /root/tinycp.txt ]; then bash /root/tinycp.txt; fi" >> "$BASHRC"
fi

echo "✅ TinyCP installer finished. Summary written to $SUMMARY"
echo "See full log: $LOG"
