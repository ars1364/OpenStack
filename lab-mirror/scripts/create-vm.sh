#!/bin/bash
##############################################################################
# create-vm.sh - Create a KVM virtual machine using virt-install
#
# Idempotent: skips if VM already exists.
#
# Creates a VM with:
#   - CPU: host-passthrough (nested KVM for OpenStack compute)
#   - Root disk: qcow2 backed by Ubuntu 24.04 cloud image (copy-on-write)
#   - Cloud-init ISO: attached as cdrom for first-boot configuration
#   - 6 NICs: one per lab network (mgmt, api, ext, octavia, storage, tunnel)
#
# Usage:
#   ./create-vm.sh <name> <vcpus> <memory_gb> <disk_gb> <pool>
#
# Example:
#   ./create-vm.sh lab-ctrl01 14 80 100 fast
##############################################################################

set -euo pipefail

NAME="$1"
VCPUS="$2"
MEMORY_GB="$3"
DISK_GB="$4"
POOL="$5"

BASE_IMAGE="/data/fast/images/ubuntu-24.04-server-cloudimg-amd64.img"

# Determine paths based on pool
case "$POOL" in
  fast)    DISK_DIR="/data/fast" ;;
  vms)     DISK_DIR="/data/vms" ;;
  storage) DISK_DIR="/data/storage" ;;
  *)       DISK_DIR="/data/fast" ;;
esac

DISK_PATH="${DISK_DIR}/${NAME}-root.qcow2"
INIT_ISO="${DISK_DIR}/${NAME}-init.iso"

# Skip if VM already exists
if sudo virsh dominfo "$NAME" &>/dev/null; then
  echo "[OK] VM '$NAME' already exists, skipping."
  exit 0
fi

# Create root disk as qcow2 overlay (copy-on-write on top of base image)
if [ ! -f "$DISK_PATH" ]; then
  echo "[INFO] Creating disk: ${DISK_PATH} (${DISK_GB}GB, backed by base image)"
  sudo qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$DISK_PATH" "${DISK_GB}G"
else
  echo "[INFO] Disk already exists: ${DISK_PATH}"
fi

# Verify cloud-init ISO exists
if [ ! -f "$INIT_ISO" ]; then
  echo "[ERROR] Cloud-init ISO not found: ${INIT_ISO}"
  echo "        Run create-cloudinit.sh first."
  exit 1
fi

# Memory in MiB for virt-install
MEMORY_MB=$((MEMORY_GB * 1024))

# Create VM with virt-install
echo "[INFO] Creating VM: ${NAME} (${VCPUS} vCPUs, ${MEMORY_GB}GB RAM, ${DISK_GB}GB disk)"

sudo virt-install \
  --name "$NAME" \
  --vcpus "$VCPUS" \
  --memory "$MEMORY_MB" \
  --cpu host-passthrough \
  --os-variant ubuntu24.04 \
  --disk "path=${DISK_PATH},format=qcow2,bus=virtio,cache=writeback" \
  --disk "path=${INIT_ISO},device=cdrom" \
  --network network=lab-mgmt,model=virtio \
  --network network=lab-api,model=virtio \
  --network network=lab-ext,model=virtio \
  --network network=lab-octavia,model=virtio \
  --network network=lab-storage,model=virtio \
  --network network=lab-tunnel,model=virtio \
  --graphics vnc,listen=127.0.0.1 \
  --serial pty \
  --console pty,target_type=serial \
  --noautoconsole \
  --autostart \
  --import

echo "[OK] VM '$NAME' created and running"
echo "     Console: sudo virsh console $NAME"
echo "     VNC:     sudo virsh vncdisplay $NAME"
