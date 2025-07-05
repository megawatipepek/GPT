#!/bin/bash
# Auto Install Script SSH + WebSocket VPN
# Fitur:
# - SSH dengan WebSocket over CDN
# - Pembuatan akun mudah
# - Manajemen masa aktif
# - Dukungan domain + SSL
# - Panel manajemen sederhana

# Install Requirements Tools
apt install ruby -y
apt install nginx -y
apt -y install wget curl
gem install lolcat
apt install python -y
apt install neofetch -y
apt install bc -y
apt install make -y
apt install cmake -y
apt install haproxy -y
apt install coreutils -y
apt install rsyslog -y
apt install net-tools -y
apt install zip -y
apt install unzip -y
apt install nano -y
apt install sed -y
apt install gnupg -y
apt install gnupg1 -y
apt install bc -y
apt install jq -y
apt install apt-transport-https -y
apt install build-essential -y
apt install dirmngr -y
apt install libxml-parser-perl -y
apt install neofetch -y
apt install git -y
apt install lsof -y
apt install libsqlite3-dev -y
apt install libz-dev -y
apt install gcc -y
apt install g++ -y
apt install libreadline-dev -y
apt install zlib1g-dev -y
apt install libssl-dev -y
apt install libssl1.0-dev -y
apt install dos2unix -y

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Script harus dijalankan sebagai root!${NC}"
  exit 1
fi

# Banner
clear
echo -e "${BLUE}"
echo "=============================================="
echo " Auto Install VPN Business Script "
echo " SSH + WebSocket | Multi User | Easy Panel "
echo "=============================================="
echo -e "${NC}"

# Fungsi untuk validasi domain
validate_domain() {
  local domain_pattern='^([a-zA-Z0-9](-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}$'
  if [[ "$1" =~ $domain_pattern ]]; then
    return 0
  else
    return 1
  fi
}

# Input domain
while true; do
  read -p "Masukkan domain Anda (contoh: myvpn.biz): " DOMAIN
  if validate_domain "$DOMAIN"; then
    break
  else
    echo -e "${RED}Format domain tidak valid! Silakan coba lagi.${NC}"
  fi
done

# Update sistem
echo -e "${YELLOW}[1/8] Memperbarui sistem...${NC}"
apt-get update -qq > /dev/null 2>&1
apt-get upgrade -y -qq > /dev/null 2>&1

# Install dependensi
echo -e "${YELLOW}[2/8] Menginstal dependensi...${NC}"
apt-get install -y -qq wget curl nano git unzip python3 python3-pip nginx > /dev/null 2>&1

# Install badvpn-udpgw
echo -e "${YELLOW}[3/8] Menginstal badvpn-udpgw...${NC}"
wget -q -O /usr/bin/badvpn-udpgw "https://raw.githubusercontent.com/daybreakersx/premscript/master/badvpn-udpgw64"
chmod +x /usr/bin/badvpn-udpgw

# Buat service badvpn
cat > /etc/systemd/system/badvpn.service << END
[Unit]
Description=BadVPN UDP Gateway
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/badvpn-udpgw --listen-addr 127.0.0.1:7300
Restart=always

[Install]
WantedBy=multi-user.target
END

# Start badvpn
systemctl daemon-reload
systemctl enable badvpn > /dev/null 2>&1
systemctl start badvpn

# Install WebSocket
echo -e "${YELLOW}[4/8] Menginstal WebSocket SSH...${NC}"
wget -q -O /usr/local/bin/ws-ssh "https://raw.githubusercontent.com/daybreakersx/premscript/master/ws-ssh"
chmod +x /usr/local/bin/ws-ssh

# Buat service WebSocket SSH
cat > /etc/systemd/system/ws-ssh.service << END
[Unit]
Description=WebSocket SSH Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ws-ssh -port 2082 -ssh 22
Restart=always

[Install]
WantedBy=multi-user.target
END

# Start WebSocket SSH
systemctl daemon-reload
systemctl enable ws-ssh > /dev/null 2>&1
systemctl start ws-ssh

# Konfigurasi Nginx
echo -e "${YELLOW}[5/8] Mengkonfigurasi Nginx...${NC}"
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/conf.d/vpn.conf << END
server {
    listen 80;
    server_name $DOMAIN;
    
    location /ssh-ws {
        proxy_pass http://127.0.0.1:2082;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location / {
        return 404;
    }
}
END

# Restart Nginx
systemctl restart nginx

# Install SSL
echo -e "${YELLOW}[6/8] Menginstal SSL...${NC}"
apt-get install -y -qq certbot python3-certbot-nginx > /dev/null 2>&1
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email
(crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet") | crontab -

# Buat script pembuatan akun
echo -e "${YELLOW}[7/8] Membuat script manajemen...${NC}"
cat > /usr/local/bin/vpn-add << END
#!/bin/bash
if [ \$# -ne 1 ]; then
  echo "Penggunaan: vpn-add <username>"
  exit 1
fi

USERNAME=\$1
PASSWORD=\$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
EXP_DATE=\$(date -d "+30 days" +"%Y-%m-%d")

useradd -m -s /bin/bash -e \$EXP_DATE \$USERNAME
echo "\$USERNAME:\$PASSWORD" | chpasswd

echo "===================================="
echo " VPN Account Created "
echo "===================================="
echo "Host: $DOMAIN"
echo "Username: \$USERNAME"
echo "Password: \$PASSWORD"
echo "Expired: \$EXP_DATE"
echo "===================================="
echo "SSH WS: wss://$DOMAIN/ssh-ws"
echo "===================================="
END

chmod +x /usr/local/bin/vpn-add

# Buat script manajemen
cat > /usr/local/bin/vpn-menu << 'END'
#!/bin/bash
# VPN Management Menu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

while true; do
  clear
  echo -e "${BLUE}"
  echo "===================================="
  echo " VPN Account Management "
  echo "===================================="
  echo -e "${NC}"
  echo "1. Buat Akun Baru"
  echo "2. Perpanjang Akun"
  echo "3. Hapus Akun"
  echo "4. List Akun"
  echo "5. Cek Masa Aktif"
  echo "6. Exit"
  echo -e "${BLUE}====================================${NC}"
  
  read -p "Pilih menu [1-6]: " choice
  
  case $choice in
    1)
      read -p "Masukkan username: " username
      vpn-add $username
      ;;
    2)
      read -p "Masukkan username: " username
      read -p "Tambahkan hari aktif: " days
      EXP_DATE=$(date -d "+$days days" +"%Y-%m-%d")
      usermod -e $EXP_DATE $username
      echo -e "${GREEN}Akun $username diperpanjang hingga $EXP_DATE${NC}"
      ;;
    3)
      read -p "Masukkan username: " username
      userdel -r $username 2>/dev/null
      echo -e "${GREEN}Akun $username telah dihapus${NC}"
      ;;
    4)
      echo -e "${BLUE}Daftar Akun VPN:${NC}"
      echo "------------------------------------"
      echo "Username | Expire Date"
      echo "------------------------------------"
      for user in $(awk -F: '$7 ~ /\/bash/ {print $1}' /etc/passwd); do
        expire=$(chage -l $user | grep "Account expires" | cut -d: -f2)
        echo "$user | $expire"
      done
      echo "------------------------------------"
      ;;
    5)
      read -p "Masukkan username: " username
      expire=$(chage -l $username | grep "Account expires" | cut -d: -f2)
      echo -e "${YELLOW}Masa aktif $username: $expire${NC}"
      ;;
    6)
      echo "Keluar..."
      exit 0
      ;;
    *)
      echo -e "${RED}Pilihan tidak valid!${NC}"
      ;;
  esac
  
  read -p "Tekan Enter untuk melanjutkan..."
done
END

chmod +x /usr/local/bin/vpn-menu

# Buat file info
echo -e "${YELLOW}[8/8] Membuat file info...${NC}"
cat > /root/vpn-info.txt << END
====================================
 VPN Server Information
====================================
Domain: $DOMAIN
SSH Port: 22
WebSocket URL: wss://$DOMAIN/ssh-ws
UDPGW Port: 7300

Untuk membuat akun:
1. vpn-add username
2. vpn-menu (menu interaktif)

====================================
END

# Selesai
clear
echo -e "${GREEN}"
echo "======================================"
echo " INSTALASI BERHASIL "
echo "======================================"
echo -e "${NC}"
echo "Informasi server telah disimpan di:"
echo "/root/vpn-info.txt"
echo ""
echo "Perintah yang tersedia:"
echo "1. vpn-add <username>  - Buat akun baru"
echo "2. vpn-menu           - Panel manajemen"
echo ""
echo -e "${GREEN}======================================${NC}"
echo ""

# Reboot jika diperlukan
read -p "Reboot server sekarang? (y/n): " reboot_choice
if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
  reboot
fi
