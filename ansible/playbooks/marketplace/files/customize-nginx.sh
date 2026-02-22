#!/bin/bash
# customize-nginx.sh - Post-deploy customization for Nginx marketplace image
# Usage: Run via cloud-init or manually after first boot

set -euo pipefail

DOMAIN="${1:-}"
BACKEND_PORT="${2:-3000}"

if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <domain> [backend_port]"
    echo "Example: $0 mysite.example.com 8080"
    exit 1
fi

echo "==> Configuring Nginx reverse proxy for ${DOMAIN} -> 127.0.0.1:${BACKEND_PORT}"

# Create site config from template
sed -e "s/example.com/${DOMAIN}/g" \
    -e "s/127.0.0.1:3000/127.0.0.1:${BACKEND_PORT}/g" \
    /etc/nginx/sites-available/reverse-proxy.conf \
    > /etc/nginx/sites-available/${DOMAIN}.conf

# Enable site
ln -sf /etc/nginx/sites-available/${DOMAIN}.conf /etc/nginx/sites-enabled/${DOMAIN}.conf

# Remove default site if still enabled
rm -f /etc/nginx/sites-enabled/default

# Test and reload
nginx -t && systemctl reload nginx
echo "==> Nginx configured for ${DOMAIN}"

# Optionally request SSL cert
if command -v certbot &>/dev/null; then
    echo "==> To enable SSL, run:"
    echo "    sudo certbot --nginx -d ${DOMAIN}"
fi
