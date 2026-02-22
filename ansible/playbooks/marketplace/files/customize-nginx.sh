#!/bin/bash
# customize-nginx.sh - Chroot customization script for Nginx marketplace image
# Used by Ansible/Packer to build the Nginx image from a base Ubuntu 24.04 cloud image
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing Nginx stack ==="
apt-get update -y

apt-get install -y \
  nginx certbot python3-certbot-nginx \
  logrotate fail2ban ufw \
  curl wget jq htop net-tools

# Enable services
systemctl enable nginx fail2ban 2>/dev/null || true

# Performance-tuned nginx.conf
cat > /etc/nginx/nginx.conf << 'NGXEOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 64m;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

stream {
    include /etc/nginx/stream.d/*.conf;
}
NGXEOF

mkdir -p /etc/nginx/stream.d

# Landing page
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Nginx Ready</title></head>
<body style="font-family:sans-serif;max-width:800px;margin:50px auto;padding:20px">
<h1>⚡ Nginx Ready</h1>
<p>Nginx reverse proxy + Certbot on Ubuntu 24.04</p>
<ul>
<li>Reverse proxy template: <code>/etc/nginx/sites-available/reverse-proxy.conf</code></li>
<li>Static site template: <code>/etc/nginx/sites-available/static-site.conf</code></li>
<li>SSL: <code>sudo certbot --nginx -d yourdomain.com</code></li>
<li>Fail2ban: <code>sudo fail2ban-client status</code></li>
<li>Rate limiting pre-configured (general: 10r/s, api: 30r/s)</li>
</ul>
<p><small>Marketplace image by CloudiNative</small></p>
</body></html>
HTMLEOF

# Fix default site to serve index.html first (not index.nginx-debian.html)
sed -i 's/index.nginx-debian.html/index.html index.nginx-debian.html/' /etc/nginx/sites-available/default 2>/dev/null || true

# Reverse proxy template
cat > /etc/nginx/sites-available/reverse-proxy.conf << 'RPEOF'
server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 300;
        proxy_connect_timeout 300;
    }

    location /health {
        access_log off;
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
RPEOF

# Static site template
cat > /etc/nginx/sites-available/static-site.conf << 'SSEOF'
server {
    listen 80;
    server_name example.com;
    root /var/www/example.com;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff2|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. {
        deny all;
    }
}
SSEOF

# Fail2ban nginx jails
cat > /etc/fail2ban/jail.d/nginx.conf << 'F2BEOF'
[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log

[nginx-limit-req]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log
F2BEOF

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "=== Nginx image customization complete ==="
