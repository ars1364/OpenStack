# Scripts — Helper Utilities

Shell scripts for VM and network lifecycle management. Used by Terraform's `local-exec` provisioners and for manual operations.

## Files

| Script | Purpose |
|--------|---------|
| `create-vm.sh` | Create a KVM/libvirt VM domain with specified resources |
| `create-network.sh` | Create libvirt networks (NAT or isolated) |
| `create-cloudinit.sh` | Generate cloud-init ISO from userdata + network-config |

## Usage

These scripts are typically called by Terraform, not directly. But they can be run standalone for debugging:

```bash
# Create a network
./create-network.sh lab-mgmt 192.168.100.0/24 nat

# Create a VM
./create-vm.sh lab-ctrl01 14 81920 /data/fast/lab-ctrl01.qcow2

# Generate cloud-init ISO (needs MAC addresses from virsh domiflist)
./create-cloudinit.sh lab-ctrl01
```

## Notes

- All scripts are idempotent — safe to re-run
- VM disks are qcow2 on NVMe (`/data/fast/`) for performance
- Cloud-init ISOs use MAC-based network config for reliable NIC naming with virtio
