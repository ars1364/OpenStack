#!/bin/bash
# Run on KVM host 95.156.253.230 to provision the cloudinative-openstack VM
# Prereqs: libvirt + KVM up, publicnet bridge connected to br0, NVMe at /var/lib/libvirt/images/nvme
set -e
NAME=cloudinative-openstack
NVMEDIR=/var/lib/libvirt/images/nvme
BASE=/var/lib/libvirt/images/noble-server-cloudimg-amd64.img

[ -f $NVMEDIR/${NAME}.qcow2 ] || qemu-img create -f qcow2 -F qcow2 -b $BASE $NVMEDIR/${NAME}.qcow2 800G

virt-install --connect=qemu:///system --name=$NAME \
  --memory=98304 --vcpus=24 \
  --osinfo=ubuntu24.04 --import \
  --disk path=$NVMEDIR/${NAME}.qcow2,format=qcow2,bus=virtio,cache=none,io=native \
  --disk path=/var/lib/libvirt/images/seed/${NAME}-seed.iso,device=cdrom,bus=sata,readonly=on \
  --network network=publicnet,model=virtio,mac=52:54:00:c1:00:01 \
  --network network=publicnet,model=virtio,mac=52:54:00:c1:00:02 \
  --cpu host-passthrough,migratable=on,topology.sockets=2,topology.cores=12,topology.threads=1 \
  --features kvm.hidden.state=off --graphics none \
  --console pty,target_type=serial --noautoconsole
