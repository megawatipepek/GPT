#!/bin/bash
# Auto Install SSH WS Tunneling via Cloudflare
# Fitur:
# - SSH WebSocket Tunneling via Cloudflare
# - Menu pembuatan akun elegan
# - Manajemen masa aktif
# - Auto SSL dengan Cloudflare
# - Optimasi untuk tunneling

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Script harus dijalankan sebagai root!${NC}"
  exit 1
fi

# Banner
clear
echo -e "${CYAN}"
cat << "EOF"
  _____ _____ _    _ _______ ______  _____
 / ____|_   _| |  | |__   __|  ____|/ ____|
| (___   | | | |__| |  | |  | |__  | (___  
 \___ \  | | |  __  |  | |  |  __|  \___ \ 
 ____) |_| |_| |  | |_ |_|  | |____ ____) |
|_____/|_____|_|  |_(_)_____|______|_____/ 
EOF
echo -e "${NC}"
echo -e "${YELLOW}=== Auto Install SSH WS Tunneling via Cloudflare ==="
echo -e "${NC}"

# Fungsi validasi input
validate_input() {
  if [[ -z "$1" ]]; then
    echo -e "${RED}Input tidak boleh kosong!${NC}"
    return 1
  else
    return 0
  fi
}

# Input Cloudflare
echo -e "${YELLOW}[+] Konfigurasi Cloudflare${NC}"
while true; do
  read -p "Masukkan email Cloudflare Anda: " CF_EMAIL
  if validate_input "$CF_EMAIL"; then break; fi
done

while true; do
  read -p "Masukkan Global API Key Cloudflare: " CF_API_KEY
  if validate_input "$CF_API_KEY"; then break; fi
done

while true; do
  read -p "Masukkan Zone ID Cloudflare: " CF_ZONE_ID
  if validate_input "$CF_ZONE_ID"; then break; fi
done

while true; do
  read -p "Masukkan subdomain untuk tunneling (contoh: tunnel): " SUBDOMAIN
  if validate_input "$SUBDOMAIN"; then break; fi
done

while true; do
  read -p "Masukkan domain utama Anda (contoh: myvpn.net): " DOMAIN
  if validate_input "$DOMAIN"; then break; fi
done

FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"

# Update sistem
echo -e "${YELLOW}[1/8] Memperbarui sistem...${NC}"
apt-get update -qq > /dev/null 2>&1
apt-get upgrade -y -qq > /dev/null 2>&1

# Install dependensi
echo -e "${YELLOW}[2/8] Menginstal dependensi...${NC}"
apt-get install -y -qq wget curl nano git unzip python3 python3-pip jq > /dev/null 2>&1

# Install Cloudflared
echo -e "${YELLOW}[3/8] Menginstal Cloudflared...${NC}"
wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb > /dev/null 2>&1
rm -f cloudflared-linux-amd64.deb

# Buat konfigurasi tunnel
echo -e "${YELLOW}[4/8] Membuat Cloudflare Tunnel...${NC}"
cloudflared tunnel create ssh-tunnel > /dev/null 2>&1
TUNNEL_ID=$(cloudflared tunnel list | grep ssh-tunnel | awk '{print $1}')

# Buat credentials file
cloudflared tunnel token --id $TUNNEL_ID > /root/tunnel-cred.json

# Buat konfigurasi tunnel
mkdir -p /etc/cloudflared
cat > /etc/cloudflared/config.yml <<EOF
tunnel: $TUNNEL_ID
credentials-file: /root/tunnel-cred.json
ingress:
  - hostname: $FULL_DOMAIN
    service: ssh://localhost:22
  - service: http_status:404
EOF

# Buat service untuk Cloudflare Tunnel
cat > /etc/systemd/system/cloudflared.service <<EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# Start Cloudflare Tunnel
systemctl daemon-reload
systemctl enable cloudflared > /dev/null 2>&1
systemctl start cloudflared

# Setup DNS di Cloudflare
echo -e "${YELLOW}[5/8] Setup DNS Cloudflare...${NC}"
curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
  -H "X-Auth-Email: $CF_EMAIL" \
  -H "X-Auth-Key: $CF_API_KEY" \
  -H "Content-Type: application/json" \
  --data "{\"type\":\"CNAME\",\"name\":\"$SUBDOMAIN\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" > /dev/null 2>&1

# Install WebSocket SSH
echo -e "${YELLOW}[6/8] Menginstal WebSocket SSH...${NC}"
wget -q -O /usr/local/bin/ws-ssh "https://raw.githubusercontent.com/daybreakersx/premscript/master/ws-ssh"
chmod +x /usr/local/bin/ws-ssh

# Buat service WebSocket SSH
cat > /etc/systemd/system/ws-ssh.service <<EOF
[Unit]
Description=WebSocket SSH Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ws-ssh -port 2082 -ssh 22
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Start WebSocket SSH
systemctl daemon-reload
systemctl enable ws-ssh > /dev/null 2>&1
systemctl start ws-ssh

# Buat menu manajemen akun
echo -e "${YELLOW}[7/8] Membuat menu manajemen akun...${NC}"
cat > /usr/local/bin/tunnel-manager <<'EOF'
#!/bin/bash
# SSH Tunnel Account Manager

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Config
DOMAIN="$(cat /etc/cloudflared/config.yml | grep hostname | awk '{print $2}')"
TUNNEL_IP="$(curl -s ifconfig.me)"

generate_password() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c 16
}

show_banner() {
  clear
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════╗"
  echo "║          SSH TUNNEL MANAGEMENT           ║"
  echo "╠══════════════════════════════════════════╣"
  echo -e "${NC}"
}

show_account_info() {
  local username=$1
  local password=$2
  local expire_date=$3
  
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════╗"
  echo "║           ACCOUNT INFORMATION            ║"
  echo "╠══════════════════════════════════════════╣"
  echo -e "${BLUE} Username\t: ${GREEN}$username${NC}"
  echo -e "${BLUE} Password\t: ${GREEN}$password${NC}"
  echo -e "${BLUE} Expire Date\t: ${GREEN}$expire_date${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════${NC}"
  echo -e "${BLUE} SSH Method (Direct)${NC}"
  echo -e " Host\t\t: ${GREEN}$DOMAIN${NC}"
  echo -e " Port\t\t: ${GREEN}22${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════${NC}"
  echo -e "${BLUE} SSH Method (WebSocket)${NC}"
  echo -e " URL\t\t: ${GREEN}wss://$DOMAIN/ssh-ws${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════${NC}"
  echo -e "${BLUE} Tunnel IP (For Whitelisting)${NC}"
  echo -e " IP Address\t: ${GREEN}$TUNNEL_IP${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
  echo ""
}

while true; do
  show_banner
  echo -e " ${CYAN}1. ${NC}Create New Tunnel Account"
  echo -e " ${CYAN}2. ${NC}Extend Account Duration"
  echo -e " ${CYAN}3. ${NC}Delete Tunnel Account"
  echo -e " ${CYAN}4. ${NC}List All Accounts"
  echo -e " ${CYAN}5. ${NC}Show Active Connections"
  echo -e " ${CYAN}6. ${NC}Server Information"
  echo -e " ${CYAN}7. ${NC}Exit"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
  echo ""
  
  read -p " Select menu [1-7]: " choice
  
  case $choice in
    1)
      read -p " Enter username: " username
      if id "$username" &>/dev/null; then
        echo -e "${RED}Error: User already exists!${NC}"
      else
        password=$(generate_password)
        read -p " Duration (days): " days
        expire_date=$(date -d "+$days days" +"%Y-%m-%d")
        
        useradd -m -s /bin/bash -e $expire_date $username
        echo "$username:$password" | chpasswd
        
        show_account_info "$username" "$password" "$expire_date"
      fi
      ;;
    2)
      read -p " Enter username: " username
      if id "$username" &>/dev/null; then
        read -p " Add days: " days
        new_expire=$(date -d "+$days days" +"%Y-%m-%d")
        usermod -e $new_expire $username
        echo -e "${GREEN}Success: Account $username extended to $new_expire${NC}"
      else
        echo -e "${RED}Error: User not found!${NC}"
      fi
      ;;
    3)
      read -p " Enter username: " username
      if id "$username" &>/dev/null; then
        userdel -r $username
        echo -e "${GREEN}Success: Account $username deleted${NC}"
      else
        echo -e "${RED}Error: User not found!${NC}"
      fi
      ;;
    4)
      echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
      echo -e " ${BLUE}List of Tunnel Accounts${NC}"
      echo -e "${CYAN}╠══════════════════════════════════════════╣${NC}"
      printf " ${CYAN}%-15s ${BLUE}%-20s${NC}\n" "Username" "Expire Date"
      echo -e "${CYAN}╠══════════════════════════════════════════╣${NC}"
      for user in $(awk -F: '$7 ~ /\/bash/ {print $1}' /etc/passwd); do
        expire=$(chage -l $user | grep "Account expires" | cut -d: -f2)
        printf " %-15s %-20s\n" "$user" "$expire"
      done
      echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
      ;;
    5)
      echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
      echo -e " ${BLUE}Active Tunnel Connections${NC}"
      echo -e "${CYAN}╠══════════════════════════════════════════╣${NC}"
      who
      echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
      ;;
    6)
      show_banner
      echo -e " ${BLUE}Server Information${NC}"
      echo -e "${CYAN}╠══════════════════════════════════════════╣${NC}"
      echo -e " ${CYAN}Domain\t: ${GREEN}$DOMAIN${NC}"
      echo -e " ${CYAN}Tunnel IP\t: ${GREEN}$TUNNEL_IP${NC}"
      echo -e " ${CYAN}WebSocket URL\t: ${GREEN}wss://$DOMAIN/ssh-ws${NC}"
      echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
      ;;
    7)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo -e "${RED}Error: Invalid selection!${NC}"
      ;;
  esac
  
  read -p "Press Enter to continue..."
done
EOF

chmod +x /usr/local/bin/tunnel-manager

# Buat file info
echo -e "${YELLOW}[8/8] Membuat file informasi...${NC}"
cat > /root/tunnel-info.txt <<EOF
============================================
       SSH TUNNEL SERVER INFORMATION       
============================================
Domain Tunnel    : $FULL_DOMAIN
WebSocket URL    : wss://$FULL_DOMAIN/ssh-ws
Tunnel IP        : $(curl -s ifconfig.me)

Untuk mengelola akun:
1. Jalankan perintah: tunnel-manager
2. Atau buat akun cepat dengan:
   useradd -m -s /bin/bash username
   passwd username

Fitur:
- SSH Direct via Cloudflare Tunnel
- WebSocket SSH Tunnel
- Menu manajemen elegan
- Auto SSL via Cloudflare

============================================
EOF

# Selesai
clear
echo -e "${GREEN}"
echo "============================================"
echo "       INSTALASI BERHASIL DILAKUKAN        "
echo "============================================"
echo -e "${NC}"
echo -e "Informasi server telah disimpan di ${YELLOW}/root/tunnel-info.txt${NC}"
echo ""
echo -e "Gunakan perintah ${CYAN}tunnel-manager${NC} untuk mengelola akun tunneling"
echo ""
echo -e "Akses tunneling via:"
echo -e "  - SSH Direct: ${GREEN}$FULL_DOMAIN${NC} port 22"
echo -e "  - WebSocket: ${GREEN}wss://$FULL_DOMAIN/ssh-ws${NC}"
echo ""
echo -e "${GREEN}============================================${NC}"
echo ""

# Reboot jika diperlukan
read -p "Reboot server sekarang? (y/n): " reboot_choice
if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
  reboot
fi
