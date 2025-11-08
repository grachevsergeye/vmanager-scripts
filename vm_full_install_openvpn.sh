#!/bin/bash
# vm_full_install_openvpn.sh
# Robust OpenVPN server installer (Debian/Ubuntu)
# Creates working PKI + server + one client .ovpn
# Logs -> /var/log/vm_install_openvpn.log

LOG="/var/log/vm_install_openvpn.log"
SUMMARY="/root/openvpn.txt"
CLIENT_NAME="client1"
CLIENTS_DIR="/etc/openvpn/clients"
EASYRSA_DIR="/etc/openvpn/easy-rsa"

set -e
export DEBIAN_FRONTEND=noninteractive

mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "=== $(date) Starting OpenVPN installer ==="

# --- Install dependencies ---
apt-get update -y
apt-get install -y openvpn easy-rsa iptables-persistent wget ca-certificates lsb-release

# --- Prepare Easy-RSA directory ---
rm -rf "${EASYRSA_DIR}"
mkdir -p "${EASYRSA_DIR}"
if [ -d /usr/share/easy-rsa ]; then
  cp -a /usr/share/easy-rsa/* "${EASYRSA_DIR}/"
else
  wget -qO- https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.6/EasyRSA-3.1.6.tgz | tar -xz -C /tmp
  cp -a /tmp/EasyRSA-3.1.6/* "${EASYRSA_DIR}/"
fi

cd "${EASYRSA_DIR}"
chmod -R 700 "${EASYRSA_DIR}"

# --- Initialize PKI and build CA/server certs ---
./easyrsa init-pki
EASYRSA_BATCH=1 ./easyrsa build-ca nopass
EASYRSA_BATCH=1 ./easyrsa gen-req server nopass
EASYRSA_BATCH=1 ./easyrsa sign-req server server
EASYRSA_BATCH=1 ./easyrsa gen-dh
openvpn --genkey secret ta.key

# --- Server configuration ---
mkdir -p /etc/openvpn
cat > /etc/openvpn/server.conf <<EOF
port 1194
proto udp
dev tun
ca ${EASYRSA_DIR}/pki/ca.crt
cert ${EASYRSA_DIR}/pki/issued/server.crt
key ${EASYRSA_DIR}/pki/private/server.key
dh ${EASYRSA_DIR}/pki/dh.pem
tls-auth ${EASYRSA_DIR}/ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn-status.log
verb 3
EOF

# --- Copy certs/keys for OpenVPN service ---
cp -a "${EASYRSA_DIR}/pki/ca.crt" /etc/openvpn/
cp -a "${EASYRSA_DIR}/pki/issued/server.crt" /etc/openvpn/
cp -a "${EASYRSA_DIR}/pki/private/server.key" /etc/openvpn/
cp -a "${EASYRSA_DIR}/pki/dh.pem" /etc/openvpn/
cp -a "${EASYRSA_DIR}/ta.key" /etc/openvpn/
chmod 600 /etc/openvpn/*.key

# --- Enable IP forwarding and NAT ---
sysctl -w net.ipv4.ip_forward=1
grep -q '^net.ipv4.ip_forward' /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
IFACE=$(ip route get 1 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}')
if [ -n "$IFACE" ]; then
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE
  netfilter-persistent save
fi

# --- Enable and start OpenVPN service ---
systemctl enable openvpn@server
systemctl restart openvpn@server

# --- Generate client cert and .ovpn file ---
mkdir -p "${CLIENTS_DIR}"
chmod 750 "${CLIENTS_DIR}"
cd "${EASYRSA_DIR}"
EASYRSA_BATCH=1 ./easyrsa gen-req "${CLIENT_NAME}" nopass
EASYRSA_BATCH=1 ./easyrsa sign-req client "${CLIENT_NAME}"

CA=$(cat pki/ca.crt)
CERT=$(cat pki/issued/${CLIENT_NAME}.crt)
KEY=$(cat pki/private/${CLIENT_NAME}.key)
TA=$(cat ta.key)
SERVER_IP=$(hostname -I | awk '{print $1}')

cat > "${CLIENTS_DIR}/${CLIENT_NAME}.ovpn" <<EOF
client
dev tun
proto udp
remote ${SERVER_IP} 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
verb 3

<ca>
${CA}
</ca>

<cert>
${CERT}
</cert>

<key>
${KEY}
</key>

<tls-auth>
${TA}
</tls-auth>
EOF

chmod 600 "${CLIENTS_DIR}/${CLIENT_NAME}.ovpn"

# --- Summary and login display ---
cat > "${SUMMARY}" <<EOF
==============================================
✅ OpenVPN Installation Complete!

Client config: ${CLIENTS_DIR}/${CLIENT_NAME}.ovpn
Server IP: ${SERVER_IP}
Port: 1194/udp

Notes:
 - Download the .ovpn file to your device
 - Import it into any OpenVPN client
 - Keys & certs stored under: ${EASYRSA_DIR}/pki
==============================================
EOF

chmod 644 "${SUMMARY}"
grep -qF "cat ${SUMMARY}" /root/.bashrc 2>/dev/null || echo "cat ${SUMMARY}" >> /root/.bashrc
cat "${SUMMARY}"

echo "=== $(date) OpenVPN installer finished ==="
exit 0
