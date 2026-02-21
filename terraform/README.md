# Terraform — Lab VM Provisioning

Provisions 5 KVM/libvirt VMs and 6 isolated networks on the HPE DL360 Gen9 host to simulate a multi-node OpenStack cluster.

## What It Creates

### VMs (5)
| VM | vCPUs | RAM | Disk | Role |
|----|-------|-----|------|------|
| lab-ctrl01 | 14 | 80G | 100G | Controller (HA) |
| lab-ctrl02 | 12 | 64G | 100G | Controller (HA) |
| lab-ctrl03 | 12 | 64G | 100G | Controller (HA) |
| lab-comp04 | 10 | 48G | 100G | Compute + Cinder |
| lab-comp05 | 10 | 48G | 100G | Compute + Cinder |

### Networks (6)
| Network | Subnet | Type | Purpose |
|---------|--------|------|---------|
| lab-mgmt | 192.168.100.0/24 | NAT | Management, SSH |
| lab-api | 192.168.204.0/24 | NAT | OpenStack API, Kolla internal VIP |
| lab-ext | 192.168.206.0/24 | NAT | External / Floating IPs |
| lab-octavia | 192.168.202.0/24 | Isolated | Octavia load balancer |
| lab-storage | 192.168.210.0/24 | Isolated | Ceph / storage replication |
| lab-tunnel | 192.168.212.0/24 | Isolated | VXLAN tenant tunnels |

## Prerequisites

- `libvirt` + `QEMU/KVM` installed on host
- Nested virtualization enabled (`kvm_intel.nested=1`)
- Terraform ≥ 1.5
- Ubuntu 24.04 cloud image at the path defined in `variables.tf`

## Usage

```bash
cd terraform/
terraform init
terraform apply
```

## Key Design Decisions

- **`null_resource` + `local-exec` over libvirt provider**: The Terraform libvirt provider v0.9.2 was too buggy (volume handling, network XML). Shell scripts (`virsh`, `qemu-img`) are more reliable.
- **MAC-based NIC naming**: Cloud-init network config uses MAC addresses (read from `virsh domiflist` after VM creation) — the only reliable way to map NICs with virtio.
- **Nested virtualization via XSLT**: `nested-virt.xsl` template patches the libvirt XML to enable nested KVM for OpenStack compute nodes.
- **Cloud-init ISO generated post-create**: ISOs are created as a second pass because MAC addresses are only known after VM domain exists.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | VM and network definitions, provisioning logic |
| `variables.tf` | Configurable parameters (RAM, vCPUs, IPs, paths) |
| `outputs.tf` | VM IPs and connection info |
| `templates/cloud-init.yml.tpl` | Cloud-init userdata template |
| `templates/network-config.yml.tpl` | Cloud-init network config (MAC-based) |
| `templates/nested-virt.xsl` | XSLT to inject nested virt CPU flags |

## After Provisioning

1. Wait for cloud-init to finish on all VMs (~2-3 min)
2. Verify SSH: `ssh ubuntu@192.168.100.11` (ctrl01)
3. Proceed to Phase 3 (Kolla-Ansible deployment)
