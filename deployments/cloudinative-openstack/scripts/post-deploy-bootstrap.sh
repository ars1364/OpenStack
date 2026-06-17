#!/bin/bash
set -e
. /tmp/admin-openrc.sh

echo "===== cloudinative project + admin ====="
openstack project show cloudinative 2>/dev/null || \
  openstack project create --domain default --description "cloudinative demo tenant" cloudinative
openstack role add --project cloudinative --user admin admin
openstack role add --project cloudinative --user admin member 2>/dev/null || true

echo "===== flavors ====="
for spec in "cloudinative-tiny:1:1024:10" \
            "cloudinative-small:2:2048:20" \
            "cloudinative-medium:4:4096:40" \
            "cloudinative-large:8:8192:80"; do
  name=$(echo $spec | cut -d: -f1)
  vcpu=$(echo $spec | cut -d: -f2)
  ram=$(echo $spec | cut -d: -f3)
  disk=$(echo $spec | cut -d: -f4)
  openstack flavor show $name 2>/dev/null || \
    openstack flavor create --vcpus $vcpu --ram $ram --disk $disk $name
done

echo "===== external network ====="
openstack network show cloudinative-public 2>/dev/null || \
  openstack network create \
    --provider-physical-network physnet1 \
    --provider-network-type flat \
    --external \
    --share \
    cloudinative-public

openstack subnet show cloudinative-public-subnet 2>/dev/null || \
  openstack subnet create \
    --network cloudinative-public \
    --subnet-range 95.156.253.224/27 \
    --gateway 95.156.253.225 \
    --no-dhcp \
    --allocation-pool start=95.156.253.241,end=95.156.253.243 \
    --allocation-pool start=95.156.253.246,end=95.156.253.250 \
    --allocation-pool start=95.156.253.252,end=95.156.253.252 \
    --dns-nameserver 1.1.1.1 \
    --dns-nameserver 8.8.8.8 \
    cloudinative-public-subnet

echo "===== tenant network ====="
openstack network show cloudinative-tenant 2>/dev/null || \
  OS_PROJECT_NAME=cloudinative openstack network create cloudinative-tenant
openstack subnet show cloudinative-tenant-subnet 2>/dev/null || \
  OS_PROJECT_NAME=cloudinative openstack subnet create \
    --network cloudinative-tenant \
    --subnet-range 10.50.0.0/24 \
    --gateway 10.50.0.1 \
    --dns-nameserver 1.1.1.1 \
    --dns-nameserver 8.8.8.8 \
    cloudinative-tenant-subnet

echo "===== router ====="
openstack router show cloudinative-router 2>/dev/null || \
  OS_PROJECT_NAME=cloudinative openstack router create cloudinative-router
OS_PROJECT_NAME=cloudinative openstack router set --external-gateway cloudinative-public cloudinative-router 2>/dev/null || true
OS_PROJECT_NAME=cloudinative openstack router add subnet cloudinative-router cloudinative-tenant-subnet 2>/dev/null || true

echo "===== security group ====="
sg=$(OS_PROJECT_NAME=cloudinative openstack security group list -c Name -f value | grep -m1 ^default)
if [ -n "$sg" ]; then
  OS_PROJECT_NAME=cloudinative openstack security group rule create --proto icmp default 2>/dev/null || true
  OS_PROJECT_NAME=cloudinative openstack security group rule create --proto tcp --dst-port 22 default 2>/dev/null || true
  OS_PROJECT_NAME=cloudinative openstack security group rule create --proto tcp --dst-port 80 default 2>/dev/null || true
  OS_PROJECT_NAME=cloudinative openstack security group rule create --proto tcp --dst-port 443 default 2>/dev/null || true
fi

echo "===== cloudinative keypair (place admin pubkey) ====="
mkdir -p ~/.ssh
[ -f ~/.ssh/id_ed25519 ] || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q
openstack keypair show cloudinative-key 2>/dev/null || \
  openstack keypair create --public-key ~/.ssh/id_ed25519.pub cloudinative-key

echo "===== summary ====="
echo "Project: $(openstack project show cloudinative -c name -f value)"
echo "Flavors: $(openstack flavor list -c Name -f value | grep ^cloudinative- | tr '\n' ' ')"
echo "External: $(openstack network show cloudinative-public -c name -f value)"
echo "Tenant:   $(OS_PROJECT_NAME=cloudinative openstack network show cloudinative-tenant -c name -f value)"
echo "Router:   $(OS_PROJECT_NAME=cloudinative openstack router show cloudinative-router -c name -f value)"
