#!/bin/bash
# ==========================================================
# Automated 3x-ui Installer with Self-Healing APT Setup
# Works cleanly on Ubuntu 22.04+
# ==========================================================

LOG_FILE="/var/log/vm_install_3xui.log"
exec > >(tee -a "$LOG_FILE") 2>&1
set -e
trap 'echo "[ERROR] Script failed at line $LINENO" | tee -a "$LOG_FILE"' ERR

echo "========== $(date) Starting full 3x-ui installation =========="

# --- Step 0: Fix interrupted installs or dpkg locks ---
echo "[INFO] Checking and fixing dpkg/apt state..."
export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a || true
apt --fix-broken install -y || true

# --- Step 1: Update System ---
apt update -y
apt upgrade -y || apt --fix-broken install -y

# --- Step 2: Install essentials ---
apt install -y vim curl wget sudo tar lsof net-tools cron

# --- Step 3: Clean up fake 'systemctl' if installed ---
if dpkg -l | grep -q "^ii  systemctl "; then
  echo "⚠️  Removing fake systemctl package..."
  apt remove -y systemctl
fi

# --- Step 4: Create installer script ---
cat <<'EOF' > /root/vm_install_3xui.sh
#!/bin/bash
LOG_FILE="/var/log/vm_install_3xui.log"
exec > >(tee -a "$LOG_FILE") 2>&1
set -e
trap 'echo "[ERROR] Script failed at line $LINENO" | tee -a "$LOG_FILE"' ERR

echo "========== $(date) Starting 3x-ui installation =========="

export DEBIAN_FRONTEND=noninteractive
dpkg --configure -a || true
apt --fix-broken install -y || true
apt update -y
apt install -y curl wget tar sudo lsof net-tools cron

curl -L -o /tmp/install_3xui.sh https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh
chmod +x /tmp/install_3xui.sh
bash /tmp/install_3xui.sh <<EOF2
n
EOF2

systemctl enable x-ui || true
systemctl start x-ui || true

echo "✅ 3x-ui installed successfully at $(date)"
echo "Logs saved to $LOG_FILE"
EOF

chmod +x /root/vm_install_3xui.sh
bash /root/vm_install_3xui.sh

echo "✅ All steps finished at $(date)"
echo "Check logs here: $LOG_FILE"
