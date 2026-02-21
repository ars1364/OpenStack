#!/bin/bash
# PostgreSQL 16 marketplace image customization script
# Run inside chroot of Ubuntu 24.04 cloud image
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# PostgreSQL 16 (Ubuntu 24.04 default)
apt-get install -y \
  postgresql \
  postgresql-contrib \
  postgresql-client \
  pg-activity \
  pgbouncer \
  jq \
  htop \
  net-tools \
  wget \
  curl

# Enable services
systemctl enable postgresql
systemctl enable pgbouncer

# PostgreSQL performance tuning (for 4-8GB RAM typical VM)
PG_CONF="/etc/postgresql/16/main/postgresql.conf"
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" $PG_CONF
sed -i "s/shared_buffers = 128MB/shared_buffers = 256MB/" $PG_CONF
sed -i "s/#effective_cache_size = 4GB/effective_cache_size = 1GB/" $PG_CONF
sed -i "s/#maintenance_work_mem = 64MB/maintenance_work_mem = 128MB/" $PG_CONF
sed -i "s/#work_mem = 4MB/work_mem = 16MB/" $PG_CONF
sed -i "s/#max_connections = 100/max_connections = 200/" $PG_CONF
sed -i "s/#wal_buffers = -1/wal_buffers = 16MB/" $PG_CONF
sed -i "s/#checkpoint_completion_target = 0.9/checkpoint_completion_target = 0.9/" $PG_CONF
sed -i "s/#random_page_cost = 4.0/random_page_cost = 1.1/" $PG_CONF
sed -i "s/#effective_io_concurrency = 1/effective_io_concurrency = 200/" $PG_CONF
sed -i "s/#log_min_duration_statement = -1/log_min_duration_statement = 1000/" $PG_CONF
sed -i "s/#log_checkpoints = off/log_checkpoints = on/" $PG_CONF
sed -i "s/#log_connections = off/log_connections = on/" $PG_CONF
sed -i "s/#log_disconnections = off/log_disconnections = on/" $PG_CONF
sed -i "s/#log_lock_waits = off/log_lock_waits = on/" $PG_CONF

# Allow remote connections (pg_hba.conf)
PG_HBA="/etc/postgresql/16/main/pg_hba.conf"
echo "# Allow remote connections (restrict in production!)" >> $PG_HBA
echo "host    all    all    0.0.0.0/0    scram-sha-256" >> $PG_HBA

# PgBouncer basic config
cat > /etc/pgbouncer/pgbouncer.ini << 'PGEOF'
[databases]
* = host=127.0.0.1 port=5432

[pgbouncer]
listen_addr = 127.0.0.1
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
admin_users = postgres
PGEOF

# Sysctl tuning for PostgreSQL
cat > /etc/sysctl.d/postgresql.conf << 'EOF'
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
vm.swappiness = 1
EOF

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
