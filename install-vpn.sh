#!/bin/bash
# ========================================
# Installer SSH WebSocket + Cloudflare TLS
# Elegant CLI Account Creator
# ========================================

# === KONFIGURASI ===
DOMAIN="yourdomain.com"       # Ganti dengan domain kamu yang di-pointing ke VPS

# === WARNA ===
green='\033[0;32m'
blue='\033[1;34m'
red='\033[0;31m'
nc='\033[0m'

# === CEK ROOT ===
[[ $EUID -ne 0 ]] && { echo -e "${red}Harus dijalankan sebagai root!${nc}"; exit 1; }

# === UPDATE SISTEM ===
apt update -y && apt install -y curl nginx stunnel4 python3 python3-pip netcat screen unzip

# === SETUP DOMAIN ===
echo "$DOMAIN" > /etc/domain

# === KONFIG NGINX (Redirect HTTP ke HTTPS) ===
cat > /etc/nginx/sites-enabled/default <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/stunnel/stunnel.pem;
    ssl_certificate_key /etc/stunnel/stunnel.pem;

    location / {
        proxy_pass http://127.0.0.1:80;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
EOF

systemctl restart nginx

# === STUNNEL SSL CERT & CONFIG ===
mkdir -p /etc/stunnel
openssl req -new -x509 -days 1095 -nodes \
  -out /etc/stunnel/stunnel.pem \
  -keyout /etc/stunnel/stunnel.pem \
  -subj "/C=ID/ST=Indonesia/L=Jakarta/O=Tunneler/CN=$DOMAIN"

cat > /etc/stunnel/stunnel.conf <<EOF
pid = /var/run/stunnel.pid
[ws-tls]
accept = 443
connect = 80
EOF

echo "ENABLED=1" > /etc/default/stunnel4
systemctl enable stunnel4 && systemctl restart stunnel4

# === INSTALL WEBSOCKET SERVER (Python) ===
cat > /usr/local/bin/ws-server << EOF
#!/usr/bin/env python3
import asyncio, websockets, subprocess

async def handler(websocket, path):
    p = await asyncio.create_subprocess_exec(
        'nc', '127.0.0.1', '22',
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE
    )
    async def ws_to_proc():
        try:
            async for msg in websocket:
                p.stdin.write(msg)
                await p.stdin.drain()
        except: p.kill()
    async def proc_to_ws():
        try:
            while True:
                data = await p.stdout.read(1024)
                if not data: break
                await websocket.send(data)
        except: p.kill()
    await asyncio.gather(ws_to_proc(), proc_to_ws())
asyncio.get_event_loop().run_until_complete(
    websockets.serve(handler, '0.0.0.0', 80)
)
asyncio.get_event_loop().run_forever()
EOF

chmod +x /usr/local/bin/ws-server

cat > /etc/systemd/system/ws-server.service << EOF
[Unit]
Description=SSH WebSocket Server
After=network.target

[Service]
ExecStart=/usr/local/bin/ws-server
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable ws-server
systemctl start ws-server

# === MENU PEMBUATAN AKUN ELEGAN ===
cat > /usr/bin/ssh-menu << EOF
#!/bin/bash
green='\\033[0;32m'
blue='\\033[1;34m'
red='\\033[0;31m'
nc='\\033[0m'

function buat_akun() {
    echo -ne "\${blue}Username:\${nc} "; read user
    echo -ne "\${blue}Password:\${nc} "; read pass
    echo -ne "\${blue}Expired (hari):\${nc} "; read exp
    useradd -e \$(date -d "\$exp days" +%Y-%m-%d) -s /bin/false -M \$user
    echo "\$user:\$pass" | chpasswd
    IP=\$(curl -s ifconfig.me)
    echo -e "\n\${green}=== INFO AKUN SSH ===\${nc}"
    echo "Host/IP     : \$IP"
    echo "Username    : \$user"
    echo "Password    : \$pass"
    echo "Expired     : \$exp hari"
    echo "WS Port     : 80 (non-TLS)"
    echo "TLS Port    : 443"
    echo "Payload WS  :"
    echo "GET / HTTP/1.1[crlf]Host: $DOMAIN[crlf]Upgrade: websocket[crlf][crlf]"
    echo "SNI         : $DOMAIN"
}

while true; do
    echo -e "\n\${green}========= MENU SSH =========\${nc}"
    echo "1. Buat Akun SSH"
    echo "2. Keluar"
    read -p "Pilih menu [1-2]: " opt
    case \$opt in
        1) buat_akun ;;
        2) exit ;;
        *) echo -e "\${red}Pilihan tidak valid!\${nc}" ;;
    esac
done
EOF

chmod +x /usr/bin/ssh-menu

clear
echo -e "${green}INSTALLASI BERHASIL!${nc}"
echo "Jalankan perintah: ${blue}ssh-menu${nc} untuk membuat akun"
