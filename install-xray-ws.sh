#!/bin/bash

# ==========================================
# Script Instalasi SSH & Xray Core + WebSocket
# Dengan Fitur Pembuatan Akun Otomatis
# ==========================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Silakan jalankan sebagai root atau gunakan sudo${NC}"
  exit 1
fi

# Fungsi untuk membuat akun
buat_akun() {
  echo -e "${GREEN}Membuat akun baru...${NC}"
  read -p "Masukkan username: " username
  read -p "Masukkan password: " password
  read -p "Masukkan masa aktif (hari): " exp_date
  
  # Tambahkan user SSH
  useradd -e $(date -d "+$exp_date days" +"%Y-%m-%d") -s /bin/false -M $username
  echo "$username:$password" | chpasswd
  
  # Buat konfigurasi Xray untuk user
  uuid=$(xray uuid)
  email="${username}@${domain}"
  
  # Tambahkan user ke config Xray
  if jq --arg user "$email" --arg uuid "$uuid" '.inbounds[].settings.clients += [{"id":$uuid,"email":$user}]' /usr/local/etc/xray/config.json > /tmp/xray_config.json; then
    mv /tmp/xray_config.json /usr/local/etc/xray/config.json
    systemctl restart xray
  fi
  
  # Simpan info akun
  echo -e "\n${BLUE}=== Informasi Akun ===${NC}" >> /root/akun.txt
  echo -e "Username: $username" >> /root/akun.txt
  echo -e "Password: $password" >> /root/akun.txt
  echo -e "Masa Aktif: $exp_date hari" >> /root/akun.txt
  echo -e "Tanggal Kedaluwarsa: $(date -d "+$exp_date days" +"%Y-%m-%d")" >> /root/akun.txt
  echo -e "${BLUE}=== Konfigurasi Xray ===${NC}" >> /root/akun.txt
  echo -e "Protocol: VLESS + WS + TLS" >> /root/akun.txt
  echo -e "Address: $domain" >> /root/akun.txt
  echo -e "Port: 443" >> /root/akun.txt
  echo -e "ID: $uuid" >> /root/akun.txt
  echo -e "Path: /xray" >> /root/akun.txt
  echo -e "TLS: true" >> /root/akun.txt
  echo -e "\n" >> /root/akun.txt
  
  echo -e "${GREEN}Akun berhasil dibuat!${NC}"
  echo -e "Informasi akun disimpan di /root/akun.txt"
}

# Update sistem
echo -e "${YELLOW}Memperbarui sistem...${NC}"
apt update && apt upgrade -y
apt install -y curl wget sudo nano git jq

# ==========================================
# 1. Instalasi SSH
# ==========================================
echo -e "${YELLOW}Menginstal SSH...${NC}"
apt install -y openssh-server

# Konfigurasi SSH
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/g' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
echo "AllowUsers root" >> /etc/ssh/sshd_config
systemctl restart ssh

# ==========================================
# 2. Instalasi Xray Core
# ==========================================
echo -e "${YELLOW}Menginstal Xray Core...${NC}"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

# ==========================================
# 3. Instalasi Nginx sebagai WebSocket
# ==========================================
echo -e "${YELLOW}Menginstal Nginx...${NC}"
apt install -y nginx
systemctl enable nginx

# ==========================================
# 4. Buat Konfigurasi Xray dengan WebSocket
# ==========================================
read -p "Masukkan domain Anda (misal: example.com): " domain

echo -e "${YELLOW}Membuat konfigurasi Xray...${NC}"
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10000,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/xray"
        }
      }
    },
    {
      "port": 8443,
      "protocol": "trojan",
      "settings": {
        "clients": [],
        "fallbacks": [
          {
            "dest": 80
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/xray.crt",
              "keyFile": "/etc/xray/xray.key"
            }
          ]
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

# ==========================================
# 5. Buat Konfigurasi Nginx
# ==========================================
echo -e "${YELLOW}Mengkonfigurasi Nginx...${NC}"
cat > /etc/nginx/conf.d/xray.conf <<EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    server_name $domain;
    
    ssl_certificate /etc/xray/xray.crt;
    ssl_certificate_key /etc/xray/xray.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    
    location /xray {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    
    location / {
        root /var/www/html;
        index index.html;
    }
}
EOF

# Buat halaman default
mkdir -p /var/www/html
echo "<h1>Welcome to $domain</h1>" > /var/www/html/index.html

# ==========================================
# 6. Buat Sertifikat SSL
# ==========================================
echo -e "${YELLOW}Membuat sertifikat SSL...${NC}"
apt install -y socat
curl https://get.acme.sh | sh
~/.acme.sh/acme.sh --register-account -m admin@$domain
~/.acme.sh/acme.sh --issue -d $domain --standalone --keylength ec-256
~/.acme.sh/acme.sh --install-cert -d $domain --ecc \
  --fullchain-file /etc/xray/xray.crt \
  --key-file /etc/xray/xray.key

# Buat cronjob untuk renew sertifikat
echo "0 0 * * * root /root/.acme.sh/acme.sh --cron --home /root/.acme.sh > /dev/null" >> /etc/crontab

# ==========================================
# 7. Konfigurasi Firewall
# ==========================================
echo -e "${YELLOW}Mengkonfigurasi firewall...${NC}"
apt install -y ufw
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

# ==========================================
# 8. Mulai Layanan
# ==========================================
systemctl restart nginx
systemctl enable xray
systemctl restart xray

# ==========================================
# 9. Buat Menu Manajemen
# ==========================================
cat > /usr/local/bin/xray-menu <<EOF
#!/bin/bash

while true; do
  clear
  echo -e "${BLUE}=== Menu Manajemen Xray ===${NC}"
  echo -e "1. Buat akun baru"
  echo -e "2. List semua akun"
  echo -e "3. Hapus akun"
  echo -e "4. Restart layanan"
  echo -e "5. Keluar"
  echo -e ""
  read -p "Pilih opsi [1-5]: " option
  
  case \$option in
    1)
      buat_akun
      ;;
    2)
      echo -e "${GREEN}Daftar akun:${NC}"
      if [ -f "/root/akun.txt" ]; then
        cat /root/akun.txt
      else
        echo "Belum ada akun yang dibuat"
      fi
      ;;
    3)
      read -p "Masukkan username yang akan dihapus: " del_user
      if id "\$del_user" &>/dev/null; then
        userdel -f \$del_user
        sed -i "/Username: \$del_user/,/^$/d" /root/akun.txt
        echo -e "${GREEN}Akun \$del_user berhasil dihapus${NC}"
      else
        echo -e "${RED}Akun tidak ditemukan${NC}"
      fi
      ;;
    4)
      systemctl restart xray
      systemctl restart nginx
      echo -e "${GREEN}Layanan berhasil di-restart${NC}"
      ;;
    5)
      exit 0
      ;;
    *)
      echo -e "${RED}Pilihan tidak valid${NC}"
      ;;
  esac
  
  read -p "Tekan Enter untuk melanjutkan..."
done
EOF

chmod +x /usr/local/bin/xray-menu

# Tambahkan fungsi ke .bashrc
echo -e "\nbuat_akun() {\n$(declare -f buat_akun | sed '1,2d;$d')\n}" >> /root/.bashrc
echo -e "alias menu-xray='xray-menu'" >> /root/.bashrc
source /root/.bashrc

# ==========================================
# Selesai
# ==========================================
clear
echo -e "${GREEN}Instalasi selesai!${NC}"
echo -e ""
echo -e "${BLUE}Informasi Server:${NC}"
echo -e "Domain: $domain"
echo -e "IP: $(curl -s ifconfig.me)"
echo -e ""
echo -e "${BLUE}Untuk mengelola akun, jalankan:${NC}"
echo -e "menu-xray"
echo -e ""
echo -e "${BLUE}Atau langsung buat akun pertama:${NC}"
echo -e "buat_akun"
echo -e ""
echo -e "${YELLOW}Pastikan domain $domain sudah mengarah ke IP VPS ini${NC}"
