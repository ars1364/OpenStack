#!/bin/bash
# Redis marketplace image customization script
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  redis-server \
  redis-tools \
  redis-sentinel \
  curl wget jq htop net-tools

systemctl enable redis-server

# ============================================================
# Redis performance tuning
# ============================================================
REDIS_CONF="/etc/redis/redis.conf"

sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/' $REDIS_CONF
sed -i 's/^# requirepass foobared/requirepass CHANGEME/' $REDIS_CONF
sed -i 's/^# maxmemory <bytes>/maxmemory 256mb/' $REDIS_CONF
sed -i 's/^# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/' $REDIS_CONF
sed -i 's/^appendonly no/appendonly yes/' $REDIS_CONF
sed -i 's/^# appendfsync everysec/appendfsync everysec/' $REDIS_CONF
sed -i 's/^tcp-backlog 511/tcp-backlog 2048/' $REDIS_CONF
sed -i 's/^# tcp-keepalive 300/tcp-keepalive 60/' $REDIS_CONF
sed -i 's/^loglevel notice/loglevel notice/' $REDIS_CONF
sed -i 's|^logfile ""|logfile /var/log/redis/redis-server.log|' $REDIS_CONF

echo "" >> $REDIS_CONF
echo "# Security: disable dangerous commands" >> $REDIS_CONF
echo 'rename-command FLUSHDB ""' >> $REDIS_CONF
echo 'rename-command FLUSHALL ""' >> $REDIS_CONF
echo 'rename-command DEBUG ""' >> $REDIS_CONF

# Sysctl tuning
cat > /etc/sysctl.d/redis.conf << 'EOF'
vm.overcommit_memory = 1
net.core.somaxconn = 2048
EOF

# Disable THP
cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages
Before=redis-server.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable disable-thp

apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "=== Redis installed ==="
redis-server --version
redis-cli --version
