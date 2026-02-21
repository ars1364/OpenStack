#!/bin/bash
# Marketplace image customization: Docker CE on Ubuntu 24.04
# Runs inside chroot — full network access available
set -ex

export DEBIAN_FRONTEND=noninteractive

# --- Update package lists ---
apt-get update -y

# --- Install prerequisites ---
apt-get install -y ca-certificates curl gnupg

# --- Docker CE GPG key ---
# download.docker.com is accessible (not sanctions-blocked)
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# --- Docker CE APT repository ---
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu noble stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y

# --- Install Docker CE + plugins ---
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# --- Install useful tools ---
apt-get install -y \
  jq \
  htop \
  net-tools \
  wget \
  bash-completion

# --- Enable Docker services ---
systemctl enable docker
systemctl enable containerd

# --- Docker daemon configuration ---
# registry-mirrors points to local Docker Hub proxy (airgap)
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "registry-mirrors": ["https://docker.cloudinative.com"]
}
EOF

# --- Docker bash completion ---
docker completion bash > /etc/bash_completion.d/docker 2>/dev/null || true

# --- Verify installation ---
echo "=== Docker CE installed ==="
docker --version
echo "=== Disk usage ==="
df -h /
