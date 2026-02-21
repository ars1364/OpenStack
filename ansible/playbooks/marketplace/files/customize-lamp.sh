#!/bin/bash
# Marketplace image customization: LAMP Stack on Ubuntu 24.04
# Runs inside chroot — full network access available
set -ex

export DEBIAN_FRONTEND=noninteractive

# ============================================================
# Install LAMP stack
# ============================================================
apt-get update -y

apt-get install -y \
  apache2 \
  mariadb-server \
  php8.3 \
  php8.3-mysql \
  php8.3-curl \
  php8.3-gd \
  php8.3-mbstring \
  php8.3-xml \
  php8.3-zip \
  php8.3-intl \
  php8.3-bcmath \
  php8.3-soap \
  php8.3-cli \
  php8.3-common \
  php8.3-opcache \
  libapache2-mod-php8.3 \
  composer \
  certbot \
  python3-certbot-apache \
  unzip \
  curl \
  wget \
  jq \
  htop \
  net-tools

# ============================================================
# Enable services
# ============================================================
systemctl enable apache2
systemctl enable mariadb

# ============================================================
# Apache modules
# ============================================================
a2enmod rewrite ssl headers expires

# ============================================================
# PHP tuning
# ============================================================
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 64M/' /etc/php/8.3/apache2/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 64M/' /etc/php/8.3/apache2/php.ini
sed -i 's/memory_limit = 128M/memory_limit = 256M/' /etc/php/8.3/apache2/php.ini
sed -i 's/max_execution_time = 30/max_execution_time = 120/' /etc/php/8.3/apache2/php.ini

# ============================================================
# Landing page
# ============================================================
cat > /var/www/html/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html><head><title>LAMP Stack Ready</title></head>
<body style="font-family:sans-serif;max-width:800px;margin:50px auto;padding:20px">
<h1>🚀 LAMP Stack Ready</h1>
<p>Apache + MariaDB + PHP 8.3 on Ubuntu 24.04</p>
<ul>
<li><a href="/info.php">PHP Info</a></li>
<li>MariaDB: <code>sudo mysql</code></li>
<li>Web root: <code>/var/www/html/</code></li>
<li>SSL: <code>sudo certbot --apache</code></li>
</ul>
<p><small>Marketplace image by CloudiNative</small></p>
</body></html>
HTMLEOF

cat > /var/www/html/info.php << 'PHPEOF'
<?php phpinfo(); ?>
PHPEOF

# ============================================================
# Cleanup
# ============================================================
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ============================================================
# Summary
# ============================================================
echo "=== LAMP Stack installed ==="
apache2 -v 2>/dev/null | head -1
mariadb --version 2>/dev/null
php -v 2>/dev/null | head -1
echo "=== Disk usage ==="
df -h /
