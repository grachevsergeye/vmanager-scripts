#!/bin/bash
# ==========================================================
# Discordo Full Installer (final; prints instructions for using personal token)
# ==========================================================

LOG_FILE="/var/log/vm_install_discordo.log"
SUMMARY_SCRIPT="/root/discordo.txt"
INSTALLER_SH="/tmp/install_discordo.sh"

set -e
export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========== $(date) Starting Discordo installation =========="

# --- Prep & deps ---
dpkg --configure -a 2>/dev/null || true
apt-get update -y >/dev/null 2>&1
apt-get install -y git curl build-essential libx11-dev libxkbfile-dev libsecret-1-dev xwayland gnome-keyring pkg-config >/dev/null 2>&1 || true

# --- Remove old Go ---
rm -rf /usr/local/go
apt remove -y golang-go golang-doc >/dev/null 2>&1 || true

# --- Install Go 1.23.2 ---
cd /tmp
curl -fsSL -O https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# --- Clone Discordo ---
cd ~
rm -rf discordo
git clone https://github.com/ayn2op/discordo.git
cd discordo

# --- Build Discordo ---
go clean
go build .

# --- Move binary to /usr/local/bin ---
sudo mv discordo /usr/local/bin/discordo

# --- Ensure GNOME Keyring is running ---
eval $(gnome-keyring-daemon --start)
export $(gnome-keyring-daemon --start)

# --- Create summary script ---
cat > "$SUMMARY_SCRIPT" <<EOF
#!/bin/bash
echo ""
echo "=============================================="
echo "✅ Discordo installation complete!"
echo ""
echo "To run Discordo, use your personal token:"
echo ""
echo "discordo --token \"YOUR_PERSONAL_TOKEN\""
echo ""
echo "Note: QR login and 2FA currently do not work reliably."
echo "=============================================="
echo ""
EOF
chmod +x "$SUMMARY_SCRIPT"

# Add to root bashrc
if ! grep -q "bash $SUMMARY_SCRIPT" /root/.bashrc 2>/dev/null; then
  echo "bash $SUMMARY_SCRIPT" >> /root/.bashrc
fi

# Print summary immediately
bash "$SUMMARY_SCRIPT"

echo "[DONE] $(date) Installation finished."
exit 0
