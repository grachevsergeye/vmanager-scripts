#!/bin/bash
# vm_full_install_wireguard.sh
# WireGuard installer (Debian/Ubuntu friendly)
# - writes clients to /etc/wireguard/clients/client-<timestamp>.conf
# - writes summary to /root/wireguard.txt (shown at login)
# Logs -> /var/log/vm_install_wireguard.log

LOG="/var/log/vm_install_wireguard.log"
SUMMARY="/root/wireguard.txt"
WG_DIR="/etc/wireguard"
CLIENTS_DIR="${WG_DIR}/clients"

set -e
export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date) Starting WireGuard installer ==="

# deps
apt-get update -y
apt-get install -y wireguard iproute2 qrencode || true

mkdir -p "${WG_DIR}"
umask 077

# generate server keys if missing
if [ ! -f "${WG_DIR}/privatekey" ]; then
  wg genkey > "${WG_DIR}/privatekey"
  cat "${WG_DIR}/privatekey" | wg pubkey > "${WG_DIR}/publickey"
fi

SERVER_PRIV=$(cat "${WG_DIR}/privatekey")
SERVER_PUB=$(cat "${WG_DIR}/publickey")
LISTEN_PORT=51820

# server conf
cat > "${WG_DIR}/wg0.conf" <<EOF
[Interface]
Address = 10.10.0.1/24
ListenPort = ${LISTEN_PORT}
PrivateKey = ${SERVER_PRIV}
SaveConfig = true
EOF

chmod 600 "${WG_DIR}/wg0.conf"

# enable and start
systemctl enable --now wg-quick@wg0 || true

# ensure clients dir
mkdir -p "${CLIENTS_DIR}"
chmod 750 "${CLIENTS_DIR}"

# create deterministic client filename: client-<timestamp>
TS=$(date +%s)
CLIENT_NAME="client-${TS}"
CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"

CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(echo "${CLIENT_PRIV}" | wg pubkey)
SERVER_IP=$(hostname -I | awk '{print $1}')

# count next IP
USED=$(wg show wg0 allowed-ips 2>/dev/null | awk '{print $3}' | sed 's#/.*##' | sort -u)
# simple assignment: use 10.10.0.2 for first client, else next free
NEXT_IP="10.10.0.2"
for n in $(seq 2 250); do
  ipt="10.10.0.$n"
  if ! echo "$USED" | grep -q "^${ipt}$"; then
    NEXT_IP="${ipt}"
    break
  fi
done

cat > "${CLIENT_CONF}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIV}
Address = ${NEXT_IP}/24
DNS = 1.1.1.1,8.8.8.8

[Peer]
PublicKey = ${SERVER_PUB}
Endpoint = ${SERVER_IP}:${LISTEN_PORT}
AllowedIPs = 0.0.0.0/0
EOF

chmod 600 "${CLIENT_CONF}"

# add peer to running interface
wg set wg0 peer "${CLIENT_PUB}" allowed-ips "${NEXT_IP}"

# create QR (optional) next to conf
qrencode -o "${CLIENT_CONF}.png" -t PNG < "${CLIENT_CONF}" || true

# Summary file
cat > "${SUMMARY}" <<EOF
==============================================
✅ WireGuard Installation Complete!

Client config: ${CLIENT_CONF}
QR (png): ${CLIENT_CONF}.png
Server IP: ${SERVER_IP}
Listen port: ${LISTEN_PORT}

To use the client:
 - download ${CLIENT_CONF} and load it into WireGuard client
 - or use the generated PNG QR shown above

Notes:
 - Client files are stored in ${CLIENTS_DIR}
 - No reboot was scheduled by this installer
==============================================
EOF

chmod 700 "${SUMMARY}"
if ! grep -qF "bash ${SUMMARY}" /root/.bashrc 2>/dev/null; then
  echo "bash ${SUMMARY}" >> /root/.bashrc
fi

bash "${SUMMARY}"
echo "=== $(date) WireGuard installer finished ==="
exit 0
