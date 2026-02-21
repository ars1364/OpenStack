# Kolla — OpenStack Configuration

Kolla-Ansible configuration files for the lab cluster (2025.1 / Ubuntu Noble).

## Files

| File | Purpose |
|------|---------|
| `globals.yml` | Main Kolla-Ansible configuration (services, networking, backends) |
| `multinode` | Inventory mapping VMs to Kolla roles |
| `config/cinder.conf` | Cinder overrides (LVM backend, cluster name) |
| `config/glance.conf` | Glance overrides (file backend) |
| `config/neutron.conf` | Neutron overrides |
| `config/neutron/ml2_conf.ini` | ML2 plugin config (OVN, flat networks, VLAN ranges) |
| `config/nova.conf` | Nova overrides (nested virt, CPU mode) |

## Key Configuration Choices

### Networking (OVN)
- **Mechanism driver**: OVN (not OVS)
- **OVN SB relay**: Disabled (`enable_ovn_sb_db_relay: "no"`) — crashes in Kolla 2025.1 for small clusters
- **Flat networks**: `physnet1` (external), `physnet-oct` (Octavia)
- **Tunnel type**: Geneve (OVN default, not VXLAN)

### Storage
- **Glance**: File backend (not Ceph — lab simplification)
- **Cinder**: LVM on loopback (`/data/storage/cinder-volumes.img`, 20GB per node)
- **Cinder cluster**: Named cluster with etcd coordination backend

### Compute
- **CPU mode**: `host-passthrough` (enables nested virt for tenant VMs)
- **Virt type**: KVM

### Services Enabled
Core: Keystone, Glance, Nova, Neutron (OVN), Cinder, Horizon, Heat, Octavia, Barbican

### Services Disabled
Murano, Solum, Magnum, Trove, Sahara, Watcher, Vitrage, Blazar, Cloudkitty, Freezer, Senlin, Tacker, Cyborg, Masakari

## Deployment

These files are deployed to `/etc/kolla/` on the lab host. Kolla-Ansible reads them during deployment.

```bash
# Copy to /etc/kolla/ (if not already there)
sudo cp globals.yml /etc/kolla/globals.yml
sudo cp multinode /etc/kolla/multinode
sudo cp -r config/ /etc/kolla/config/
```

See the main [README](../README.md) for the full deployment procedure.

## Gotchas

1. **passlib + bcrypt 5.x**: Kolla uses bcrypt for passwords. passlib 1.7.4 has a bug with bcrypt ≥5.x. Patch `detect_wrap_bug()` to return `False`.
2. **MariaDB first**: Always deploy MariaDB separately before full deploy. Galera bootstrap exceeds the default 10s timeout.
3. **Pull before deploy**: Always `kolla-ansible pull` before `deploy` to avoid registry overload during deployment.
4. **Octavia certs**: Must generate even if Octavia is disabled — Kolla prechecks require them.
