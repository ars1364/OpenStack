#!/bin/bash
# customize-wordpress.sh - Chroot customization script for WordPress marketplace image
# Used by Ansible/Packer to build the WordPress image from a base Ubuntu 24.04 cloud image
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing WordPress stack ==="
apt-get update -y

# LAMP base
apt-get install -y \
  apache2 mariadb-server \
  php8.3 php8.3-mysql php8.3-curl php8.3-gd php8.3-mbstring \
  php8.3-xml php8.3-zip php8.3-intl php8.3-bcmath php8.3-soap \
  php8.3-cli php8.3-common php8.3-opcache php8.3-imagick \
  libapache2-mod-php8.3 \
  certbot python3-certbot-apache \
  unzip curl wget jq htop net-tools ghostscript

# Enable services & modules
systemctl enable apache2 mariadb
a2enmod rewrite ssl headers expires

# PHP tuning for WordPress
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 128M/' /etc/php/8.3/apache2/php.ini
sed -i 's/post_max_size = 8M/post_max_size = 128M/' /etc/php/8.3/apache2/php.ini
sed -i 's/memory_limit = 128M/memory_limit = 512M/' /etc/php/8.3/apache2/php.ini
sed -i 's/max_execution_time = 30/max_execution_time = 300/' /etc/php/8.3/apache2/php.ini
sed -i 's/max_input_time = 60/max_input_time = 300/' /etc/php/8.3/apache2/php.ini

# WP-CLI
curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar
mv wp-cli.phar /usr/local/bin/wp

# Download WordPress (latest)
cd /tmp
curl -sO https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz
rm -rf /var/www/html/*
cp -r wordpress/* /var/www/html/
chown -R www-data:www-data /var/www/html
rm -rf /tmp/wordpress /tmp/latest.tar.gz

# wp-config template
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
chown www-data:www-data /var/www/html/wp-config.php

# Apache vhost for WordPress
cat > /etc/apache2/sites-available/wordpress.conf << 'APEOF'
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html

    <Directory /var/www/html>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/error.log
    CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
APEOF
a2dissite 000-default
a2ensite wordpress

# .htaccess for WordPress permalinks
cat > /var/www/html/.htaccess << 'HTEOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTEOF
chown www-data:www-data /var/www/html/.htaccess

# First-boot setup script
cat > /usr/local/bin/wp-setup << 'SETUPEOF'
#!/bin/bash
# WordPress first-boot database setup
# Run: sudo wp-setup
set -e

echo "=== WordPress Setup ==="
read -p "Database name [wordpress]: " DB_NAME
DB_NAME=${DB_NAME:-wordpress}
read -p "Database user [wpuser]: " DB_USER
DB_USER=${DB_USER:-wpuser}
read -sp "Database password: " DB_PASS
echo ""

# Create database and user
mysql -u root << SQLEOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQLEOF

# Update wp-config.php
cd /var/www/html
sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
sed -i "s/username_here/${DB_USER}/" wp-config.php
sed -i "s/password_here/${DB_PASS}/" wp-config.php

# Generate security keys
KEYS=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null)
if [ -n "$KEYS" ]; then
  sed -i '/AUTH_KEY/d; /SECURE_AUTH_KEY/d; /LOGGED_IN_KEY/d; /NONCE_KEY/d; /AUTH_SALT/d; /SECURE_AUTH_SALT/d; /LOGGED_IN_SALT/d; /NONCE_SALT/d' wp-config.php
  sed -i "/put your unique phrase here/d" wp-config.php
  echo "$KEYS" >> wp-config.php
fi

echo "✅ WordPress database configured!"
echo "Visit your server's IP in a browser to complete installation."
SETUPEOF
chmod +x /usr/local/bin/wp-setup

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "=== WordPress image customization complete ==="
