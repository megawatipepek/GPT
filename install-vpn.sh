#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check root
if [ "$(id -u)" != "0" ]; then
  echo -e "${RED}Error: This script must be run as root!${NC}"
  exit 1
fi

# Variables
IPV4=$(curl -4 -s ipv4.icanhazip.com)
IPV6=$(curl -6 -s ipv6.icanhazip.com 2>/dev/null)
DOMAIN=""
UUID=$(cat /proc/sys/kernel/random/uuid)
XRAY_CONFIG="/etc/xray/config.json"
SSH_PORT="22"
WS_PORT="80"

# Check IPv6
if [ -z "$IPV6" ]; then
  echo -e "${YELLOW}Warning: IPv6 not detected on this server.${NC}"
  HAS_IPV6=false
else
  HAS_IPV6=true
  echo -e "${GREEN}IPv6 detected: ${IPV6}${NC}"
fi

# Install dependencies
apt-get update
apt-get install -y curl wget unzip git nano openssl net-tools cron socat

# Install Dropbear, OpenSSH, Stunnel
apt-get install -y dropbear openssh-server stunnel4
sed -i 's/NO_START=1/NO_START=0/g' /etc/default/stunnel4
sed -i 's/DROPBEAR_PORT=22/DROPBEAR_PORT=443/g' /etc/default/dropbear

# Configure SSH
sed -i "s/#Port 22/Port ${SSH_PORT}/g" /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
sed -i 's/#GatewayPorts no/GatewayPorts yes/g' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
systemctl restart ssh

# Install Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# Create Xray config
cat > $XRAY_CONFIG <<EOF
{
  "log": {
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-direct"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": 80,
            "xver": 1
          },
          {
            "path": "/vmess",
            "dest": 23456,
            "xver": 1
          },
          {
            "path": "/vless",
            "dest": 23456,
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "xtls",
        "xtlsSettings": {
          "alpn": [
            "http/1.1"
          ],
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
        }
      }
    },
    {
      "port": 23456,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/vmess"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

# Generate SSL certificate
openssl req -new -newkey rsa:2048 -days 365 -nodes -x509 \
  -subj "/C=US/ST=California/L=Los Angeles/O=Example/CN=www.example.com" \
  -keyout /etc/xray/xray.key -out /etc/xray/xray.crt

# Install Nginx for WebSocket
apt-get install -y nginx
cat > /etc/nginx/conf.d/websocket.conf <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name localhost;

    location /vmess {
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }

    location /vless {
        proxy_pass http://127.0.0.1:23456;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

# Restart services
systemctl restart nginx
systemctl restart xray
systemctl enable nginx
systemctl enable xray

# Create account management script
cat > /usr/bin/vps-account <<'EOF'
#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function add_user() {
  username=$1
  password=$2
  
  if [ -z "$username" ] || [ -z "$password" ]; then
    echo -e "${RED}Error: Username and password required!${NC}"
    echo "Usage: vps-account add <username> <password>"
    return 1
  fi
  
  # Add SSH user
  useradd -m -s /bin/bash $username
  echo "$username:$password" | chpasswd
  
  # Add to sudoers
  echo "$username ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
  
  echo -e "${GREEN}User $username created successfully!${NC}"
  echo -e "${YELLOW}SSH Info:${NC}"
  echo -e "Host: $(curl -4 -s ipv4.icanhazip.com)"
  echo -e "Port: 22"
  echo -e "Username: $username"
  echo -e "Password: $password"
}

function delete_user() {
  username=$1
  
  if [ -z "$username" ]; then
    echo -e "${RED}Error: Username required!${NC}"
    echo "Usage: vps-account del <username>"
    return 1
  fi
  
  userdel -r $username 2>/dev/null
  sed -i "/^$username/d" /etc/sudoers
  
  echo -e "${GREEN}User $username deleted successfully!${NC}"
}

function list_users() {
  echo -e "${YELLOW}List of users:${NC}"
  cut -d: -f1 /etc/passwd | grep -v -E "(root|sync|halt|shutdown|nobody)"
}

function show_help() {
  echo -e "${YELLOW}VPS Account Management Tool${NC}"
  echo "Usage:"
  echo "  vps-account add <username> <password>  - Add new user"
  echo "  vps-account del <username>            - Delete user"
  echo "  vps-account list                      - List all users"
  echo "  vps-account help                      - Show this help"
}

case "$1" in
  add)
    add_user "$2" "$3"
    ;;
  del)
    delete_user "$2"
    ;;
  list)
    list_users
    ;;
  help|*)
    show_help
    ;;
esac
EOF

chmod +x /usr/bin/vps-account

# Create Xray config management script
cat > /usr/bin/xray-manager <<'EOF'
#!/bin/bash

# Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

function add_config() {
  uuid=$(cat /proc/sys/kernel/random/uuid)
  email=$1
  
  if [ -z "$email" ]; then
    email="user-$(date +%s)"
  fi
  
  config_file="/etc/xray/config.json"
  temp_file="/tmp/xray_config.tmp"
  
  # Backup config
  cp $config_file "${config_file}.bak"
  
  # Add new user to VLESS config
  jq --arg uuid "$uuid" --arg email "$email" \
    '.inbounds[0].settings.clients += [{"id": $uuid, "email": $email, "flow": "xtls-rprx-direct"}]' \
    $config_file > $temp_file && mv $temp_file $config_file
  
  # Add new user to WebSocket config
  jq --arg uuid "$uuid" --arg email "$email" \
    '.inbounds[1].settings.clients += [{"id": $uuid, "email": $email}]' \
    $config_file > $temp_file && mv $temp_file $config_file
  
  systemctl restart xray
  
  echo -e "${GREEN}Xray configuration added successfully!${NC}"
  echo -e "${YELLOW}Connection Info:${NC}"
  echo -e "UUID: $uuid"
  echo -e "Email: $email"
  echo -e "Host: $(curl -4 -s ipv4.icanhazip.com)"
  echo -e "Port: 443"
  echo -e "Transport: TCP/XTLS"
  echo -e "WebSocket Path: /vmess or /vless"
}

function delete_config() {
  uuid=$1
  
  if [ -z "$uuid" ]; then
    echo -e "${RED}Error: UUID required!${NC}"
    echo "Usage: xray-manager del <uuid>"
    return 1
  fi
  
  config_file="/etc/xray/config.json"
  temp_file="/tmp/xray_config.tmp"
  
  # Backup config
  cp $config_file "${config_file}.bak"
  
  # Remove user from VLESS config
  jq --arg uuid "$uuid" \
    '(.inbounds[0].settings.clients) |= map(select(.id != $uuid))' \
    $config_file > $temp_file && mv $temp_file $config_file
  
  # Remove user from WebSocket config
  jq --arg uuid "$uuid" \
    '(.inbounds[1].settings.clients) |= map(select(.id != $uuid))' \
    $config_file > $temp_file && mv $temp_file $config_file
  
  systemctl restart xray
  
  echo -e "${GREEN}Xray configuration deleted successfully!${NC}"
}

function list_configs() {
  echo -e "${YELLOW}List of Xray configurations:${NC}"
  jq -r '.inbounds[0].settings.clients[] | "\(.email): \(.id)"' /etc/xray/config.json
}

function show_help() {
  echo -e "${YELLOW}Xray Configuration Management Tool${NC}"
  echo "Usage:"
  echo "  xray-manager add [email]    - Add new Xray config (random email if not provided)"
  echo "  xray-manager del <uuid>    - Delete Xray config"
  echo "  xray-manager list          - List all Xray configs"
  echo "  xray-manager help          - Show this help"
}

case "$1" in
  add)
    add_config "$2"
    ;;
  del)
    delete_config "$2"
    ;;
  list)
    list_configs
    ;;
  help|*)
    show_help
    ;;
esac
EOF

chmod +x /usr/bin/xray-manager

# Install jq for JSON processing
apt-get install -y jq

# Enable IPv6 if available
if [ "$HAS_IPV6" = true ]; then
  # Configure IPv6 for SSH
  sed -i "s/#AddressFamily any/AddressFamily any/g" /etc/ssh/sshd_config
  
  # Configure IPv6 for Nginx
  sed -i "s/listen 80;/listen 80;\n    listen [::]:80;/g" /etc/nginx/conf.d/websocket.conf
  
  # Configure IPv6 for Xray
  sed -i 's/"port": 443,/"port": 443,\n      "listen": "::",/g' /etc/xray/config.json
  
  # Restart services
  systemctl restart ssh
  systemctl restart nginx
  systemctl restart xray
  
  echo -e "${GREEN}IPv6 configuration applied successfully!${NC}"
fi

# Display installation summary
clear
echo -e "${GREEN}=== Installation Completed Successfully ===${NC}"
echo ""
echo -e "${YELLOW}SSH Information:${NC}"
echo -e "Host: ${IPV4}"
[ "$HAS_IPV6" = true ] && echo -e "Host IPv6: ${IPV6}"
echo -e "Port: ${SSH_PORT}"
echo -e "Username: root"
echo -e "Password: (your current root password)"
echo ""
echo -e "${YELLOW}Xray Information:${NC}"
echo -e "Protocol: VLESS + VMESS (WebSocket)"
echo -e "Address: ${IPV4}"
[ "$HAS_IPV6" = true ] && echo -e "Address IPv6: ${IPV6}"
echo -e "Port: 443 (TLS), 80 (WebSocket)"
echo -e "UUID: ${UUID}"
echo -e "WebSocket Path: /vmess or /vless"
echo -e "Transport: TCP/XTLS + WebSocket"
echo ""
echo -e "${YELLOW}Account Management Tools:${NC}"
echo -e "1. SSH User Management: ${GREEN}vps-account${NC}"
echo -e "   Usage:"
echo -e "   - Add user: vps-account add <username> <password>"
echo -e "   - Delete user: vps-account del <username>"
echo -e "   - List users: vps-account list"
echo ""
echo -e "2. Xray Config Management: ${GREEN}xray-manager${NC}"
echo -e "   Usage:"
echo -e "   - Add config: xray-manager add [email]"
echo -e "   - Delete config: xray-manager del <uuid>"
echo -e "   - List configs: xray-manager list"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo -e "- Make sure to save the UUID and connection information"
echo -e "- Configure firewall if necessary (UFW/iptables)"
echo -e "- Consider changing SSH port for better security"
echo ""
echo -e "${GREEN}Enjoy your high-performance VPN server!${NC}"
