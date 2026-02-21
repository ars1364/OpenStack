#!/bin/bash
# Marketplace image customization: Kubernetes on Ubuntu 24.04
# Runs inside chroot — full network access available
#
# Installs: containerd, kubeadm, kubelet, kubectl
# Configures: sysctl, containerd with registry mirrors, SystemdCgroup
# Pre-pulls: K8s core images via ctr (NOT crictl — see lessons learned)
set -ex

export DEBIAN_FRONTEND=noninteractive

# ============================================================
# Kernel modules & sysctl (persist across reboots)
# ============================================================
cat > /etc/modules-load.d/k8s.conf << 'EOF'
overlay
br_netfilter
EOF

# Load now for the chroot session
modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true

cat > /etc/sysctl.d/k8s.conf << 'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system 2>/dev/null || true

# ============================================================
# Disable swap (cloud images usually don't have swap, but be safe)
# ============================================================
sed -i '/\sswap\s/d' /etc/fstab
swapoff -a 2>/dev/null || true

# ============================================================
# Install prerequisites
# ============================================================
apt-get update -y
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg \
  socat \
  conntrack \
  ebtables \
  ipset \
  ipvsadm \
  jq \
  htop \
  net-tools \
  wget \
  bash-completion

# ============================================================
# Install containerd (from Docker CE repo — accessible from Iran)
# ============================================================
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu noble stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y containerd.io

# ============================================================
# Configure containerd: SystemdCgroup + registry mirrors
# ============================================================
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable SystemdCgroup (required for kubeadm)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Add config_path for registry mirror host configs
# This enables the /etc/containerd/certs.d/ directory
sed -i '/\[plugins."io.containerd.grpc.v1.cri".registry\]/a\      config_path = "/etc/containerd/certs.d"' /etc/containerd/config.toml

# ============================================================
# Containerd registry mirrors via hosts.toml
# ============================================================
# NOTE: These work with `ctr --hosts-dir` but NOT with CRI/crictl/kubeadm.
# CRI has a known limitation where it ignores hosts.toml mirror configs.
# Users needing to pull additional images from Iran should use:
#   ctr -n k8s.io images pull --hosts-dir /etc/containerd/certs.d <image>
# Pre-pulled images (below) cover kubeadm init requirements.

declare -A MIRRORS=(
  ["registry.k8s.io"]="https://k8s.cloudinative.com"
  ["docker.io"]="https://docker.cloudinative.com"
  ["quay.io"]="https://quay.cloudinative.com"
  ["ghcr.io"]="https://ghcr.cloudinative.com"
  ["gcr.io"]="https://gcr.cloudinative.com"
)

for registry in "${!MIRRORS[@]}"; do
  mirror="${MIRRORS[$registry]}"
  dir="/etc/containerd/certs.d/${registry}"
  mkdir -p "$dir"
  cat > "${dir}/hosts.toml" << TOML
server = "${mirror}"

[host."${mirror}"]
  capabilities = ["pull", "resolve"]
  skip_verify = false
TOML
done

# ============================================================
# crictl config (points to containerd)
# ============================================================
cat > /etc/crictl.yaml << 'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
EOF

# ============================================================
# Install kubeadm, kubelet, kubectl
# ============================================================
# pkgs.k8s.io is accessible (CNAMEs to prod-cdn.packages.k8s.io)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | \
  gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# ============================================================
# Enable services
# ============================================================
systemctl enable containerd
systemctl enable kubelet

# ============================================================
# Pre-pull K8s core images
# ============================================================
# We use `ctr` with --hosts-dir to pull through cloudinative mirrors.
# We do NOT use `kubeadm config images pull` or `crictl pull` because
# the CRI plugin ignores hosts.toml mirror configs (known containerd bug).
#
# The images are stored in the k8s.io namespace so kubeadm finds them.

# Start containerd temporarily for image pulls
containerd &
CONTAINERD_PID=$!
sleep 3

# Get the image list from kubeadm
IMAGES=$(kubeadm config images list 2>/dev/null || echo "")
if [ -z "$IMAGES" ]; then
  # Fallback: hardcoded for v1.32
  IMAGES="
registry.k8s.io/kube-apiserver:v1.32.12
registry.k8s.io/kube-controller-manager:v1.32.12
registry.k8s.io/kube-scheduler:v1.32.12
registry.k8s.io/kube-proxy:v1.32.12
registry.k8s.io/etcd:3.5.16-0
registry.k8s.io/coredns/coredns:v1.12.0
registry.k8s.io/pause:3.10
"
fi

PULL_FAILED=0
for img in $IMAGES; do
  echo "=== Pulling $img ==="
  if ctr -n k8s.io images pull --hosts-dir /etc/containerd/certs.d \
    --platform linux/amd64 "$img"; then
    echo "  ✓ $img"
  else
    echo "  ✗ FAILED: $img (will be pulled on first boot)"
    PULL_FAILED=$((PULL_FAILED + 1))
  fi
done

# Show what we got
echo "=== Pre-pulled images ==="
ctr -n k8s.io images list -q 2>/dev/null || true

# Stop containerd
kill $CONTAINERD_PID 2>/dev/null || true
wait $CONTAINERD_PID 2>/dev/null || true

# ============================================================
# kubectl bash completion
# ============================================================
kubectl completion bash > /etc/bash_completion.d/kubectl 2>/dev/null || true
kubeadm completion bash > /etc/bash_completion.d/kubeadm 2>/dev/null || true

# ============================================================
# Summary
# ============================================================
echo "=== Kubernetes image build complete ==="
echo "kubeadm: $(kubeadm version -o short 2>/dev/null || echo 'installed')"
echo "kubelet: $(kubelet --version 2>/dev/null || echo 'installed')"
echo "kubectl: $(kubectl version --client -o yaml 2>/dev/null | grep gitVersion || echo 'installed')"
echo "containerd: $(containerd --version 2>/dev/null || echo 'installed')"
echo "Pre-pull failures: $PULL_FAILED"
echo "=== Disk usage ==="
df -h /
