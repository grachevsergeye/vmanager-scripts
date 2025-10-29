#!/bin/bash
# ==========================================================
# TinyCP Full Installer (shows panel credentials at login)
# ==========================================================

LOG="/var/log/vm_install_tinycp.log"
SUMMARY="/root/tinycp.txt"

exec >>"$LOG" 2>&1
set -e
export DEBIAN_FRONTEND=noninteractive

echo "=== $(date) TinyCP installer started ==="

# Fix & deps
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y wget curl sudo lsb-release || true

# Run official TinyCP installer
echo "[*] Running official TinyCP installer..."
wget -qO- https://tinycp.com/install.sh | bash || true

IP=$(hostname -I | awk '{print $1}')

# Try to find password in installer log
PASS=$(grep -Eo 'Password: [^[:space:]]+' "$LOG" | tail -n1 | awk '{print $2}')
[ -z "$PASS" ] && PASS=$(grep -Ei 'admin|password' "$LOG" | tail -n3 | tr '\n' ' ')
[ -z "$PASS" ] && PASS="(see $LOG for details)"

# Create summary script
cat > "$SUMMARY" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo -e "\033[1;32m✅ TinyCP Installation Complete!\033[0m"
echo ""
echo "Date: $(date)"
echo ""
echo "Panel: http://${IP}:8080"
echo "Login: admin"
echo "Password: $PASS"
echo "=============================================="
echo ""
EOF

chmod +x "$SUMMARY"

# Ensure it runs at login
BASHRC="/root/.bashrc"
if ! grep -qF "bash /root/tinycp.txt" "$BASHRC" 2>/dev/null; then
  echo "" >> "$BASHRC"
  echo "# show TinyCP credentials at login" >> "$BASHRC"
  echo "if [ -f /root/tinycp.txt ]; then bash /root/tinycp.txt; fi" >> "$BASHRC"
fi

echo "✅ TinyCP installer finished. Summary written to $SUMMARY"
echo "See full log: $LOG"
