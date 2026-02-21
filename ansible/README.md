# Ansible — Playbooks & Inventory

All Ansible automation for the OpenStack lab and production operations.

## Directory Structure

```
ansible/
├── inventory/
│   └── hosts.yml          # Lab VM inventory (ctrl01-03, comp04-05)
├── playbooks/
│   ├── host-prepare.yml   # Phase 1: Prepare HPE host (packages, mounts, libvirt)
│   ├── kolla-deploy.yml   # Phase 3: Full Kolla-Ansible deployment orchestration
│   ├── create-monarc-vm.yml  # Production: Provision Monarc VM on OpenStack
│   └── marketplace/       # Marketplace image builder (see marketplace/README.md)
```

## Playbooks

### `host-prepare.yml` — Phase 1: Host Preparation

Prepares the bare-metal HPE server for running the lab:
- Installs KVM/libvirt/QEMU, Terraform, Ansible
- Mounts data disks (`/data/storage`, `/data/vms`, `/data/fast`)
- Enables nested virtualization
- Configures APT to use cloudinative mirrors

```bash
ansible-playbook -i inventory/hosts.yml playbooks/host-prepare.yml
```

### `kolla-deploy.yml` — Phase 3: OpenStack Deployment

Orchestrates the full Kolla-Ansible 2025.1 deployment across 5 lab VMs:
- Bootstrap servers
- Generate Octavia certificates
- Pre-pull images from `quay.cloudinative.com`
- Deploy MariaDB first (Galera bootstrap timeout fix)
- Deploy all remaining services
- Post-deploy tasks

```bash
ansible-playbook -i inventory/hosts.yml playbooks/kolla-deploy.yml
```

> **Critical order**: `pull` → `deploy --tags mariadb` → `deploy`. Never skip the MariaDB-first step.

### `create-monarc-vm.yml` — Production VM Provisioning

Creates and configures a VM on the production OpenStack cluster:
- Creates port on provider network (direct public IP)
- Launches instance with cloud-init userdata
- Installs Docker, Node.js, Go, pip
- Configures APT mirrors and mounts data volume

```bash
ansible-playbook playbooks/create-monarc-vm.yml
```

### `marketplace/` — Marketplace Image Builder

Builds and uploads pre-configured Glance images (Docker CE, Kubernetes, etc.) for customer self-service. Airgap-ready with cloudinative mirrors.

**See [marketplace/README.md](playbooks/marketplace/README.md) for full documentation.**

## Inventory

`inventory/hosts.yml` defines the 5 lab VMs with their management IPs:
- `ctrl01` (192.168.100.11), `ctrl02` (.12), `ctrl03` (.13)
- `comp04` (192.168.100.14), `comp05` (.15)

Production hosts are accessed via SSH jump through `xadmin@172.40.30.21` (server01).
