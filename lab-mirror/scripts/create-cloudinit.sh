#!/bin/bash
##############################################################################
# create-cloudinit.sh - Generate cloud-init ISO for a lab VM
#
# Creates a cloud-init ISO with MAC-based network matching (since virtio
# NIC naming is unpredictable on Ubuntu cloud images).
#
# Usage:
#   ./create-cloudinit.sh <hostname> <mgmt_ip> <ssh_pub_key> <pool>
#
# Reads MAC addresses from virsh domiflist. If VM doesn't exist yet,
# skips network config (cloud-init will use DHCP as fallback).
##############################################################################

set -euo pipefail

HOSTNAME="$1"
MGMT_IP="$2"
SSH_PUB_KEY="$3"
POOL="$4"

LAST_OCTET="${MGMT_IP##*.}"
API_IP="192.168.204.${LAST_OCTET}"
EXT_IP="192.168.206.${LAST_OCTET}"
OCT_IP="192.168.202.${LAST_OCTET}"
STOR_IP="192.168.210.${LAST_OCTET}"
TUN_IP="192.168.212.${LAST_OCTET}"

case "$POOL" in
  fast)    OUTDIR="/data/fast" ;;
  vms)     OUTDIR="/data/vms" ;;
  storage) OUTDIR="/data/storage" ;;
  *)       OUTDIR="/data/fast" ;;
esac

WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

# --- Resolve MAC addresses from VM definition (if exists) ---
get_mac() {
  local vm="$1" net="$2"
  sudo virsh domiflist "$vm" 2>/dev/null | awk -v net="$net" '$3==net {print $5}'
}

MAC_MGMT=$(get_mac "$HOSTNAME" "lab-mgmt")
MAC_API=$(get_mac "$HOSTNAME" "lab-api")
MAC_EXT=$(get_mac "$HOSTNAME" "lab-ext")
MAC_OCT=$(get_mac "$HOSTNAME" "lab-octavia")
MAC_STOR=$(get_mac "$HOSTNAME" "lab-storage")
MAC_TUN=$(get_mac "$HOSTNAME" "lab-tunnel")

# --- meta-data ---
cat > "${WORKDIR}/meta-data" <<EOF
instance-id: ${HOSTNAME}
local-hostname: ${HOSTNAME}
EOF

# --- user-data ---
cat > "${WORKDIR}/user-data" <<EOF
#cloud-config
hostname: ${HOSTNAME}
fqdn: ${HOSTNAME}.lab.local
manage_etc_hosts: true
timezone: UTC

ssh_authorized_keys:
  - ${SSH_PUB_KEY}

ssh_pwauth: false
disable_root: true

apt:
  primary:
    - arches: [amd64]
      uri: https://archive.cloudinative.com/ubuntu/
  security:
    - arches: [amd64]
      uri: https://security.cloudinative.com/ubuntu/

packages:
  - python3
  - python3-pip
  - python3-venv
  - docker.io
  - bridge-utils
  - net-tools
  - jq
  - chrony
  - lvm2
  - thin-provisioning-tools
  - ca-certificates
  - curl

runcmd:
  - mkdir -p /etc/docker
  - |
    cat > /etc/docker/daemon.json <<'DOCKER'
    {
      "registry-mirrors": ["https://docker.cloudinative.com"],
      "log-driver": "json-file",
      "log-opts": { "max-size": "10m", "max-file": "3" },
      "storage-driver": "overlay2"
    }
    DOCKER
  - systemctl enable docker
  - systemctl restart docker
  - usermod -aG docker ubuntu
  - |
    cat > /etc/sysctl.d/99-openstack.conf <<'SYSCTL'
    net.ipv4.ip_forward=1
    net.ipv4.conf.all.rp_filter=0
    net.ipv4.conf.default.rp_filter=0
    net.bridge.bridge-nf-call-iptables=1
    net.bridge.bridge-nf-call-ip6tables=1
    SYSCTL
  - modprobe br_netfilter
  - echo "br_netfilter" >> /etc/modules-load.d/openstack.conf
  - sysctl --system

final_message: "${HOSTNAME} ready for Kolla-Ansible deployment"
EOF

# --- network-config (MAC-based matching) ---
if [ -n "$MAC_MGMT" ]; then
  cat > "${WORKDIR}/network-config" <<EOF
version: 2
ethernets:
  mgmt:
    match:
      macaddress: "${MAC_MGMT}"
    set-name: mgmt0
    addresses: ["${MGMT_IP}/24"]
    routes:
      - to: default
        via: 192.168.100.1
    nameservers:
      addresses: [192.168.100.1, 8.8.8.8]
  api:
    match:
      macaddress: "${MAC_API}"
    set-name: api0
    addresses: ["${API_IP}/24"]
  ext:
    match:
      macaddress: "${MAC_EXT}"
    set-name: ext0
    addresses: ["${EXT_IP}/24"]
  octavia:
    match:
      macaddress: "${MAC_OCT}"
    set-name: oct0
    addresses: ["${OCT_IP}/24"]
  storage:
    match:
      macaddress: "${MAC_STOR}"
    set-name: stor0
    addresses: ["${STOR_IP}/24"]
  tunnel:
    match:
      macaddress: "${MAC_TUN}"
    set-name: tun0
    addresses: ["${TUN_IP}/24"]
EOF
  echo "[INFO] Network config: MAC-based matching"
else
  # Fallback: DHCP on all interfaces (VM not created yet)
  cat > "${WORKDIR}/network-config" <<EOF
version: 2
ethernets:
  id0:
    match:
      name: "en*"
    dhcp4: true
EOF
  echo "[WARN] VM not found, using DHCP fallback network config"
fi

# Generate ISO
ISO_PATH="${OUTDIR}/${HOSTNAME}-init.iso"
sudo genisoimage -output "$ISO_PATH" \
  -volid cidata -joliet -rock \
  "${WORKDIR}/meta-data" \
  "${WORKDIR}/user-data" \
  "${WORKDIR}/network-config" 2>/dev/null

echo "[OK] Cloud-init ISO: ${ISO_PATH}"
