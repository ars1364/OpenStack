# OpenStack Lab - Local Mirror/Stage

Replicate production OpenStack cluster (Kolla-Ansible 2025.1) on local HPE DL360 Gen9.

## Architecture

- **Source:** 5-node production cluster (server01-05) via WireGuard
- **Target:** Single hypervisor running 5 KVM VMs to simulate multi-node topology
- **Deployment:** Kolla-Ansible 2025.1 (Ubuntu Noble)
- **Images:** Pulled via `quay.cloudinative.com` (Nexus proxy)

## Host Specs (HPE DL360 Gen9)

- CPU: 72 cores, Intel Xeon E5-2697 v4
- RAM: 377 GB
- Storage:
  - `/` (sda): 931 GB boot
  - `/data/storage` (sdb1): 3.6 TB - Cinder, images, backups
  - `/data/vms` (sdc1): 1.1 TB - VM disks
  - `/data/fast` (nvme0n1p1): 931 GB NVMe - OS disks, ephemeral

## Lab VMs

| VM | vCPUs | RAM | Role | Mgmt IP | API IP |
|----|-------|-----|------|---------|--------|
| lab-ctrl01 | 14 | 80G | Controller | 192.168.100.11 | 192.168.204.11 |
| lab-ctrl02 | 12 | 64G | Controller | 192.168.100.12 | 192.168.204.12 |
| lab-ctrl03 | 12 | 64G | Controller | 192.168.100.13 | 192.168.204.13 |
| lab-comp04 | 10 | 48G | Compute | 192.168.100.14 | 192.168.204.14 |
| lab-comp05 | 10 | 48G | Compute | 192.168.100.15 | 192.168.204.15 |

**VIPs:** Internal=192.168.204.10, External=192.168.206.10

## Networks (6 total)

| Network | Subnet | Type | Purpose |
|---------|--------|------|---------|
| lab-mgmt | 192.168.100.0/24 | NAT | Management / SSH |
| lab-api | 192.168.204.0/24 | NAT | API / Kolla internal |
| lab-ext | 192.168.206.0/24 | NAT | External / Floating IPs |
| lab-octavia | 192.168.202.0/24 | Isolated | Octavia LB |
| lab-storage | 192.168.210.0/24 | Isolated | Storage replication |
| lab-tunnel | 192.168.212.0/24 | Isolated | VXLAN tunnels |

## Phases

### Phase 1: Host Preparation
```bash
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/host-prepare.yml
```

### Phase 2: VM Provisioning
```bash
cd terraform && terraform init && terraform apply
```
> **Important:** Cloud-init ISOs must be generated AFTER VMs exist — MAC addresses
> are read from `virsh domiflist` for reliable NIC naming. See [Terraform Notes](#terraform-notes).

### Phase 3: OpenStack Deployment
```bash
# Set environment
export ANSIBLE_CONFIG=/etc/kolla/ansible.cfg
export VIRTUAL_ENV=/opt/kolla-venv
export PATH=/opt/kolla-venv/bin:$PATH
KOLLA="kolla-ansible -i /etc/kolla/multinode"

# Step 1: Bootstrap
$KOLLA bootstrap-servers

# Step 2: Generate Octavia certs (required even if not using Octavia yet)
$KOLLA octavia-certificates

# Step 3: Prechecks
$KOLLA prechecks

# Step 4: Pull ALL images first (avoid registry overload during deploy)
$KOLLA pull

# Step 5: Deploy MariaDB first (Galera bootstrap needs time)
$KOLLA deploy --tags mariadb
# Verify: ssh to ctrl nodes, check `docker ps | grep mariadb` shows healthy

# Step 6: Deploy remaining services
$KOLLA deploy

# Step 7: Post-deploy
$KOLLA post-deploy
```

## Registry Mirrors (Mandatory — Airgap/Offline)

**All traffic must go through local Nexus proxies. Zero direct public internet access.**

| Original | Mirror | Used By |
|----------|--------|---------|
| quay.io | quay.cloudinative.com | Kolla container images |
| Docker Hub | docker.cloudinative.com | Docker daemon mirror |
| Docker CE APT | download.cloudinative.com | Docker packages on VMs |
| Ubuntu APT | archive.cloudinative.com / security.cloudinative.com | OS packages |
| PyPI | npm.cloudinative.com/repository/pypi-proxy/simple/ | pip (host + VMs) |
| Ansible Galaxy / opendev | **Vendored** in `vendor/` | Ansible collections |

### Offline Assets (`vendor/`)
| File | Purpose |
|------|---------|
| `ansible-collections-2025.1.tar.gz` | All required Ansible collections (pre-packaged) |
| `requirements-kolla-venv.txt` | Pinned pip requirements for reproducibility |

The playbook auto-detects the vendor tarball and uses it for offline install.
If absent, it falls back to online install (opendev.org).

## Lessons Learned

See [LESSONS.md](LESSONS.md) for the full list with detailed explanations.

### Key Pitfalls (Quick Reference)

| Symptom | Fix |
|---------|-----|
| "Hostname has to resolve uniquely" | Disable `manage_etc_hosts`, use API IPs only in `/etc/hosts` |
| "cinder-volumes VG not found" | Create loopback VG on all nodes before prechecks |
| "cinder_cluster_name not set" | Set `cinder_cluster_name` + `cinder_coordination_backend` in globals |
| MariaDB timeout during deploy | Deploy MariaDB separately first (`--tags mariadb`) |
| "password cannot be longer than 72 bytes" | Patch passlib for bcrypt 5.x compat |
| OVN SB relay crash / port 16641 timeout | `enable_ovn_sb_db_relay: "no"` in globals |
| "physnet-oct unknown" | Add to ML2 `flat_networks` + bridge mappings in globals |
| 503 from registry during deploy | Always `pull` before `deploy` |
| Public docker.com repo on nodes | Audit `/etc/apt/sources.list.d/` after bootstrap |

### Correct Deployment Order
```
bootstrap-servers → audit repos → octavia-certificates → prechecks → pull → deploy --tags mariadb → deploy → post-deploy
```
