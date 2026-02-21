#!/bin/bash
# Marketplace image customization script: Node.js 22 LTS
# Used by virt-customize or chroot to prepare the image
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y

# Node.js 22 LTS (NodeSource)
apt-get install -y ca-certificates curl gnupg
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --batch --yes --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y nodejs

# PM2 (process manager)
npm install -g pm2

# Nginx (reverse proxy) + certbot
apt-get install -y nginx certbot python3-certbot-nginx

# Useful tools
apt-get install -y jq htop net-tools wget build-essential git

# Yarn
npm install -g yarn

# Enable services
systemctl enable nginx

# Nginx reverse proxy template
cat > /etc/nginx/sites-available/node-app << 'NGXEOF'
server {
    listen 80;
    server_name _;
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
    }
}
NGXEOF

# Landing page
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>Node.js Ready</title></head>
<body style="font-family:sans-serif;max-width:800px;margin:50px auto;padding:20px">
<h1>🟢 Node.js Ready</h1>
<p>Node.js 22 LTS + PM2 + Nginx on Ubuntu 24.04</p>
<ul>
<li>Node: <code>node --version</code></li>
<li>NPM: <code>npm --version</code></li>
<li>PM2: <code>pm2 start app.js</code></li>
<li>Nginx proxy template: <code>/etc/nginx/sites-available/node-app</code></li>
<li>SSL: <code>sudo certbot --nginx</code></li>
</ul>
<p><small>Marketplace image by CloudiNative</small></p>
</body></html>
HTMLEOF

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "=== Node.js installed ==="
node --version
npm --version
pm2 --version
nginx -v 2>&1
