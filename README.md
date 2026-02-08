# OpenStack Infrastructure as Code

Terraform + Ansible provisioning for OpenStack VMs on the Aries cluster (`aries.cloudinative.com`, region `dc1`).

## Architecture

```
terraform/          → Infrastructure provisioning (VM, volumes, network)
ansible/            → Configuration management (DNS, Docker, Node.js, Go, runner)
scripts/            → Utility scripts (runner registration)
```

## Quick Start

### 1. Provision Infrastructure (Terraform)

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your credentials

terraform init
terraform plan
terraform apply
```

This creates:
- **Boot volume** (20GB SSD) from Ubuntu 24.04 image
- **Data volume** (2TB HDD) for Docker, builds, and runner workspace
- **VM** (C4R8: 4 vCPU, 8GB RAM) on Provider network with public IP
- Cloud-init configures password auth, DNS, and mounts the data disk

### 2. Configure VM (Ansible)

```bash
cd ansible/

# Update inventory with the VM IP from terraform output
# inventory/hosts.ini:
#   keemiyamahour-runner ansible_host=<IP> ansible_user=ubuntu ansible_password=<password>

ansible-playbook site.yml
```

Roles applied:
| Role | What it does |
|------|-------------|
| `dns` | Disables systemd-resolved, sets Iranian DNS (Shecan/Radar) |
| `common` | Base packages, data disk mount, timezone |
| `docker` | Docker CE with data-root on /data/docker |
| `nodejs` | Node.js 22 via NodeSource |
| `golang` | Go 1.23.6 |
| `github-runner` | GitHub Actions runner binary (registration separate) |

Run individual roles with tags:
```bash
ansible-playbook site.yml --tags docker
ansible-playbook site.yml --tags dns,common
```

### 3. Register GitHub Actions Runner

```bash
# SSH into the VM, then:
/data/actions-runner/../../scripts/setup-runner.sh <GITHUB_PAT> <owner/repo> [name] [labels]

# Example:
./scripts/setup-runner.sh ghp_xxx ars1364/keemiya-website keemiyamahour "self-hosted,linux,x64,openstack"
```

Or from the control machine:
```bash
scp scripts/setup-runner.sh ubuntu@<VM_IP>:/tmp/
ssh ubuntu@<VM_IP> '/tmp/setup-runner.sh ghp_xxx ars1364/keemiya-website'
```

## Cluster Reference

| Item | Value |
|------|-------|
| Region | dc1 |
| Auth URL | http://172.30.204.10:5000/v3 |
| Provider Network | VLAN on physnet1 (public IPs) |
| Volume Backends | `bus` (SSD/Ceph) / `eco` (HDD/Ceph) |
| Flavors | C4R8 (4c/8G), C8R16, etc. |
| Images | Ubuntu24, Ubuntu22, WinSrv22/25 |

## DNS Note

Iranian DNS servers (Shecan, Radar) are unreachable from the Provider network segment. The playbook configures:
- **4.2.2.4 (Level3))
- **8.8.8.8 (Google))

4.2.2.4 and 8.8.8.8 are confirmed working and resolve all required endpoints.
