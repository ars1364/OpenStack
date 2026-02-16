#cloud-config
# ============================================================================
# Cloud-Init for OpenStack Lab VMs
#
# Configures:
#   - Hostname and timezone
#   - SSH access (key-based only)
#   - APT mirrors → cloudinative.com (no public internet)
#   - Docker CE from cloudinative.com mirror
#   - Nested virtualization support
#   - NTP sync
# ============================================================================

hostname: ${hostname}
fqdn: ${fqdn}
# LESSON: Must be false — kolla prechecks requires unique hostname resolution
# to api_interface IPs only. manage_etc_hosts: true adds mgmt IPs causing
# "Hostname has to resolve uniquely" failures.
manage_etc_hosts: false
timezone: UTC

# SSH - key-based auth only
ssh_authorized_keys:
  - ${ssh_pub_key}

ssh_pwauth: false
disable_root: true

# ---------------------------------------------------------------------------
# APT Configuration
# All packages pulled from cloudinative.com Nexus proxy.
# No direct internet access required.
# ---------------------------------------------------------------------------
apt:
  primary:
    - arches: [amd64]
      uri: https://archive.cloudinative.com/ubuntu/
  security:
    - arches: [amd64]
      uri: https://security.cloudinative.com/ubuntu/

# ---------------------------------------------------------------------------
# Packages
# Core packages needed for Kolla-Ansible deployment target.
# ---------------------------------------------------------------------------
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
  - gnupg

# ---------------------------------------------------------------------------
# Runcmd
# Post-boot commands to finalize the VM for Kolla-Ansible.
# ---------------------------------------------------------------------------
runcmd:
  # Configure Docker to use cloudinative.com registry mirror
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

  # Add ubuntu user to docker group
  - usermod -aG docker ubuntu

  # Enable IP forwarding (required for Neutron)
  - sysctl -w net.ipv4.ip_forward=1
  - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.d/99-openstack.conf

  # Disable reverse path filtering (required for Neutron DVR)
  - sysctl -w net.ipv4.conf.all.rp_filter=0
  - sysctl -w net.ipv4.conf.default.rp_filter=0
  - echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.d/99-openstack.conf
  - echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.d/99-openstack.conf

  # Bridge networking for Neutron
  - modprobe br_netfilter
  - echo "br_netfilter" >> /etc/modules-load.d/openstack.conf
  - sysctl -w net.bridge.bridge-nf-call-iptables=1
  - sysctl -w net.bridge.bridge-nf-call-ip6tables=1
  - echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.d/99-openstack.conf
  - echo "net.bridge.bridge-nf-call-ip6tables=1" >> /etc/sysctl.d/99-openstack.conf

# Final message
final_message: "${hostname} ready for Kolla-Ansible deployment"
