#!/bin/bash
# vm_full_install_openvpn.sh
# OpenVPN server installer (Debian/Ubuntu focused)
# - produces /etc/openvpn/clients/<client>.ovpn
# - writes summary to /root/openvpn.txt and shows it on root login
# Logs: /var/log/vm_install_openvpn.log

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

# install deps
apt-get update -y
apt-get install -y openvpn easy-rsa iptables-persistent wget ca-certificates || true

# prepare easy-rsa tree (use distribution path if present)
if [ -d /usr/share/easy-rsa ]; then
  cp -a /usr/share/easy-rsa "${EASYRSA_DIR}"
else
  mkdir -p "${EASYRSA_DIR}"
  wget -qO- https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.6/EasyRSA-3.1.6.tgz | tar -xz -C /tmp
  cp -a /tmp/EasyRSA-3.1.6/* "${EASYRSA_DIR}/"
fi

cd "${EASYRSA_DIR}"
chmod -R 700 "${EASYRSA_DIR}"

# init PKI and build CA, server certs
./easyrsa init-pki
./easyrsa --batch build-ca nopass
./easyrsa --batch gen-req server nopass
./easyrsa --batch sign-req server server
./easyrsa gen-dh || true
openvpn --genkey --secret ta.key || true

# create server config
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
cipher AES-256-CBC
keepalive 10 120
persist-key
persist-tun
user nobody
group nogroup
status /var/log/openvpn-status.log
verb 3
EOF

# copy keys into /etc/openvpn for service to find
mkdir -p /etc/openvpn/easy-rsa
cp -a "${EASYRSA_DIR}/pki/ca.crt" /etc/openvpn/ca.crt
cp -a "${EASYRSA_DIR}/pki/issued/server.crt" /etc/openvpn/server.crt
cp -a "${EASYRSA_DIR}/pki/private/server.key" /etc/openvpn/server.key
cp -a "${EASYRSA_DIR}/pki/dh.pem" /etc/openvpn/dh.pem
cp -a "${EASYRSA_DIR}/ta.key" /etc/openvpn/ta.key
chmod 600 /etc/openvpn/*key

# enable forwarding and NAT
sysctl -w net.ipv4.ip_forward=1
sed -i '/^net.ipv4.ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# add masquerade for outgoing interface
IFACE=$(ip route get 1 | awk '{for(i=1;i<=NF;i++){if($i=="dev"){print $(i+1);exit}}}')
if [ -n "$IFACE" ]; then
  iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$IFACE" -j MASQUERADE || true
  netfilter-persistent save || true
fi

# enable & start openvpn
systemctl enable --now openvpn@server || systemctl restart openvpn || true

# ensure clients dir
mkdir -p "${CLIENTS_DIR}"
chmod 750 "${CLIENTS_DIR}"

# Generate client cert & ovpn
cd "${EASYRSA_DIR}"
./easyrsa gen-req "${CLIENT_NAME}" nopass
./easyrsa sign-req client "${CLIENT_NAME}"

# build .ovpn file with inline certs
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

# Write summary and ensure it's shown at login
cat > "${SUMMARY}" <<EOF
==============================================
✅ OpenVPN Installation Complete!

Client ovpn: ${CLIENTS_DIR}/${CLIENT_NAME}.ovpn
Server IP: ${SERVER_IP}
Port: 1194/udp

Notes:
 - Download the .ovpn file from the path above
 - OpenVPN server stores certs/keys in ${EASYRSA_DIR}/pki
==============================================
EOF
chmod 700 "${SUMMARY}"
if ! grep -qF "bash ${SUMMARY}" /root/.bashrc 2>/dev/null; then
  echo "bash ${SUMMARY}" >> /root/.bashrc
fi

# Print now
bash "${SUMMARY}"

echo "=== $(date) OpenVPN installer finished ==="
exit 0
