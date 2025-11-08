#!/bin/bash
# ==========================================================
# OpenVPN Auto Installer (fixed version)
# ==========================================================

set -e
export DEBIAN_FRONTEND=noninteractive
LOG_FILE="/var/log/openvpn_install.log"

echo "=== Starting OpenVPN installation ($(date)) ===" | tee -a "$LOG_FILE"

apt-get update -y >/dev/null 2>&1
apt-get install -y openvpn easy-rsa >/dev/null 2>&1

make-cadir ~/openvpn-ca
cd ~/openvpn-ca

# Configure Easy-RSA
cat > vars <<EOF
set_var EASYRSA_REQ_COUNTRY    "US"
set_var EASYRSA_REQ_PROVINCE   "CA"
set_var EASYRSA_REQ_CITY       "SanFrancisco"
set_var EASYRSA_REQ_ORG        "ExampleOrg"
set_var EASYRSA_REQ_EMAIL      "admin@example.com"
set_var EASYRSA_REQ_OU         "Community"
EOF

# Build CA, server, and client
./easyrsa init-pki
echo | ./easyrsa build-ca nopass
./easyrsa gen-req server nopass
echo "yes" | ./easyrsa sign-req server server
./easyrsa gen-dh
openvpn --genkey secret pki/ta.key

# Client generation
./easyrsa gen-req client nopass
echo "yes" | ./easyrsa sign-req client client

# Create OpenVPN server config
mkdir -p /etc/openvpn/server
cat > /etc/openvpn/server/server.conf <<EOF
port 1194
proto udp
dev tun
ca /root/openvpn-ca/pki/ca.crt
cert /root/openvpn-ca/pki/issued/server.crt
key /root/openvpn-ca/pki/private/server.key
dh /root/openvpn-ca/pki/dh.pem
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status openvpn-status.log
verb 3
EOF

systemctl enable openvpn-server@server.service
systemctl start openvpn-server@server.service

# Generate .ovpn client file
CLIENT_CONF=/root/openvpn-client.ovpn
cat > $CLIENT_CONF <<EOF
client
dev tun
proto udp
remote $(curl -s ifconfig.me) 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
<ca>
$(cat pki/ca.crt)
</ca>
<cert>
$(cat pki/issued/client.crt)
</cert>
<key>
$(cat pki/private/client.key)
</key>
<tls-auth>
$(cat pki/ta.key)
</tls-auth>
key-direction 1
EOF

echo "✅ OpenVPN installed successfully."
echo "Client config: $CLIENT_CONF"
