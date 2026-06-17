#!/bin/bash
# Build the cloud-init seed ISO for cloudinative-openstack VM on KVM host 95.156.253.230
# Run on the KVM host
set -e
mkdir -p /tmp/openstack-seed
cd /tmp/openstack-seed

# meta-data
cat > meta-data <<META
instance-id: cloudinative-openstack
local-hostname: openstack
META

# network-config (v2)
cat > network-config <<NET
version: 2
ethernets:
  ens3:
    addresses: [95.156.253.231/27]
    gateway4: 95.156.253.225
    nameservers:
      addresses: [46.245.69.222, 1.1.1.1]
    mtu: 1500
  ens4:
    accept-ra: false
    dhcp4: false
    dhcp6: false
NET

# user-data
cat > user-data <<UD
#cloud-config
hostname: openstack
fqdn: openstack.cloudinative.com
preserve_hostname: false
package_update: false
write_files:
  - path: /etc/hosts
    content: |
      127.0.0.1 localhost
      95.156.253.231 openstack openstack.cloudinative.com
      95.156.253.232 openstack-internal
      95.156.253.235 openstack-external
  - path: /etc/modules-load.d/kvm-nested.conf
    content: |
      kvm-intel
      vhost_net
  - path: /etc/sysctl.d/99-openstack.conf
    content: |
      net.bridge.bridge-nf-call-iptables=1
      net.bridge.bridge-nf-call-ip6tables=1
      net.ipv4.ip_forward=1
      net.ipv4.conf.all.rp_filter=0
      net.ipv4.conf.default.rp_filter=0
  - path: /etc/systemd/resolved.conf.d/no-stub.conf
    content: |
      [Resolve]
      DNSStubListener=no
apt:
  preserve_sources_list: false
  primary:
    - arches: [default]
      uri: https://apt.cloudinative.com/ubuntu
  security:
    - arches: [default]
      uri: https://apt.cloudinative.com/ubuntu
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh-authorized-keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINEFqcK9DXKDDOZBKZi+vRfvIfn... ahmad-key"  # replace with Ahmad's actual pubkey
runcmd:
  - modprobe br_netfilter
  - sysctl --system
UD

genisoimage -output cloudinative-openstack-seed.iso -volid cidata -joliet -rock user-data meta-data network-config
ls -la cloudinative-openstack-seed.iso
