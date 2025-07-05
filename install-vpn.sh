#!/bin/bash
# Auto Install SSH + WebSocket VPN Business
# Fitur:
# - SSH over WebSocket via Nginx
# - Panel manajemen akun
# - Pembuatan akun otomatis
# - Masa aktif akun
# - Multi-user support

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Script harus dijalankan sebagai root!${NC}"
  exit 1
fi

# Banner
clear
echo -e "${BLUE}"
cat << "EOF"
╔═╗╔═╗╦  ╔═╗╔═╗╔╦╗╔═╗╦═╗╔╦╗
╚═╗║╣ ║  ║ ║╠═╝ ║ ║ ║╠╦╝ ║ 
╚═╝╚═╝╩═╝╚═╝╩  ╩ ╚═╝╩╚═ ╩ 
EOF
echo -e "${NC}"
echo -e "${YELLOW}=== Auto Install VPN Business with WebSocket ==="
echo -e "${NC}"

# Fungsi validasi domain
validate_domain() {
  local domain_regex='^([a-zA-Z0-9](-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}$'
  [[ $1 =~ $domain_regex ]] && return 0 || return 1
}

# Input domain
while true; do
  read -p "Masukkan domain Anda (contoh: myvpn.id): " DOMAIN
  if validate_domain "$DOMAIN"; then
    break
  else
    echo -e "${RED}Format domain tidak valid! Silakan coba lagi.${NC}"
  fi
done

# Update sistem
echo -e "${YELLOW}[1/8] Memperbarui sistem...${NC}"
apt update -y && apt upgrade -y
apt install -y curl wget nano git unzip

# Install dependensi
echo -e "${YELLOW}[2/8] Menginstal dependensi...${NC}"
apt install -y nginx python3 python3-pip openssl

# Install WebSocket
echo -e "${YELLOW}[3/8] Menginstal WebSocket SSH...${NC}"
wget -O /usr/local/bin/ws-ssh https://raw.githubusercontent.com/daybreakersx/premscript/master/ws-ssh
chmod +x /usr/local/bin/ws-ssh

# Buat service WebSocket
cat > /etc/systemd/system/ws-ssh.service <<EOF
[Unit]
Description=WebSocket SSH Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ws-ssh -port 2082 -ssh 22
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

# Start WebSocket service
systemctl daemon-reload
systemctl enable ws-ssh
systemctl start ws-ssh

# Konfigurasi Nginx
echo -e "${YELLOW}[4/8] Mengkonfigurasi Nginx...${NC}"
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/conf.d/vpn.conf <<EOF
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
EOF

# Install SSL dengan Certbot
echo -e "${YELLOW}[5/8] Menginstal SSL...${NC}"
apt install -y certbot python3-certbot-nginx
certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email

# Update Nginx config untuk SSL
cat > /etc/nginx/conf.d/vpn.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

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
EOF

systemctl restart nginx

# Buat script manajemen akun
echo -e "${YELLOW}[6/8] Membuat script manajemen...${NC}"
cat > /usr/local/bin/vpn-manager <<'EOF'
#!/bin/bash
# VPN Account Manager

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

generate_password() {
  tr -dc A-Za-z0-9 </dev/urandom | head -c 12
}

show_banner() {
  clear
  echo -e "${BLUE}"
  echo "===================================="
  echo " VPN BUSINESS MANAGEMENT SYSTEM "
  echo "===================================="
  echo -e "${NC}"
}

while true; do
  show_banner
  echo "1. Buat Akun Baru"
  echo "2. Perpanjang Akun"
  echo "3. Hapus Akun"
  echo "4. List Semua Akun"
  echo "5. Cek Pengguna Aktif"
  echo "6. Exit"
  echo -e "${BLUE}====================================${NC}"
  
  read -p "Pilih menu [1-6]: " choice
  
  case $choice in
    1)
      read -p "Masukkan username: " username
      if id "$username" &>/dev/null; then
        echo -e "${RED}User sudah ada!${NC}"
      else
        password=$(generate_password)
        read -p "Masa aktif (hari): " days
        expire_date=$(date -d "+$days days" +"%Y-%m-%d")
        
        useradd -m -s /bin/bash -e $expire_date $username
        echo "$username:$password" | chpasswd
        
        echo -e "${GREEN}"
        echo "===================================="
        echo " AKUN BERHASIL DIBUAT "
        echo "===================================="
        echo "Host: $DOMAIN"
        echo "Username: $username"
        echo "Password: $password"
        echo "Expired: $expire_date"
        echo "WebSocket: wss://$DOMAIN/ssh-ws"
        echo "===================================="
        echo -e "${NC}"
      fi
      ;;
    2)
      read -p "Masukkan username: " username
      if id "$username" &>/dev/null; then
        read -p "Tambahkan hari aktif: " days
        new_expire=$(date -d "+$days days" +"%Y-%m-%d")
        usermod -e $new_expire $username
        echo -e "${GREEN}Akun $username diperpanjang hingga $new_expire${NC}"
      else
        echo -e "${RED}User tidak ditemukan!${NC}"
      fi
      ;;
    3)
      read -p "Masukkan username: " username
      if id "$username" &>/dev/null; then
        userdel -r $username
        echo -e "${GREEN}Akun $username telah dihapus${NC}"
      else
        echo -e "${RED}User tidak ditemukan!${NC}"
      fi
      ;;
    4)
      echo -e "${BLUE}Daftar Akun VPN:${NC}"
      echo "===================================="
      printf "%-15s %-20s\n" "Username" "Expire Date"
      echo "===================================="
      for user in $(awk -F: '$7 ~ /\/bash/ {print $1}' /etc/passwd); do
        expire=$(chage -l $user | grep "Account expires" | cut -d: -f2)
        printf "%-15s %-20s\n" "$user" "$expire"
      done
      echo "===================================="
      ;;
    5)
      echo -e "${BLUE}Pengguna Aktif:${NC}"
      echo "===================================="
      who
      echo "===================================="
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
EOF

chmod +x /usr/local/bin/vpn-manager

# Buat cronjob untuk auto-renew SSL
echo -e "${YELLOW}[7/8] Membuat cronjob auto-renew SSL...${NC}"
(crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet") | crontab -

# Buat file info
echo -e "${YELLOW}[8/8] Membuat file informasi...${NC}"
cat > /root/vpn-info.txt <<EOF
====================================
 VPN BUSINESS SERVER INFORMATION
====================================
Domain: $DOMAIN
WebSocket URL: wss://$DOMAIN/ssh-ws

Untuk manajemen akun:
1. Jalankan perintah: vpn-manager
2. Atau buat akun langsung dengan:
   vpn-add username days

Fitur:
- Pembuatan akun mudah
- Masa aktif customizable
- WebSocket over SSL
- Multi-user support

====================================
EOF

# Buat shortcut pembuatan akun
cat > /usr/local/bin/vpn-add <<EOF
#!/bin/bash
if [ \$# -lt 1 ]; then
  echo "Usage: vpn-add <username> [days]"
  exit 1
fi

username=\$1
days=\${2:-30} # Default 30 hari
password=\$(tr -dc A-Za-z0-9 </dev/urandom | head -c 12)
expire_date=\$(date -d "+\$days days" +"%Y-%m-%d")

useradd -m -s /bin/bash -e \$expire_date \$username
echo "\$username:\$password" | chpasswd

echo "===================================="
echo " VPN Account Created "
echo "===================================="
echo "Host: $DOMAIN"
echo "Username: \$username"
echo "Password: \$password"
echo "Expired: \$expire_date"
echo "WebSocket: wss://$DOMAIN/ssh-ws"
echo "===================================="
EOF

chmod +x /usr/local/bin/vpn-add

# Selesai
clear
echo -e "${GREEN}"
echo "======================================"
echo " INSTALASI BERHASIL DILAKUKAN "
echo "======================================"
echo -e "${NC}"
echo -e "Informasi server telah disimpan di ${YELLOW}/root/vpn-info.txt${NC}"
echo ""
echo -e "Gunakan perintah berikut untuk manajemen:"
echo -e "1. ${GREEN}vpn-manager${NC} - Panel manajemen interaktif"
echo -e "2. ${GREEN}vpn-add username [days]${NC} - Buat akun cepat"
echo ""
echo -e "Akses WebSocket VPN via: ${BLUE}wss://$DOMAIN/ssh-ws${NC}"
echo ""
echo -e "${GREEN}======================================${NC}"
echo ""

# Reboot jika diperlukan
read -p "Reboot server sekarang? (y/n): " reboot_choice
if [[ "$reboot_choice" == "y" || "$reboot_choice" == "Y" ]]; then
  reboot
fi
