# Lessons Learned - OpenStack Lab Deployment

## Kolla-Ansible

1. **Always `pull` before `deploy`** — Separates registry/network issues from deployment logic. Nexus can return 503 under heavy concurrent load (5 nodes pulling simultaneously).

2. **Deploy MariaDB separately first** — Galera cluster bootstrap on fresh nodes takes longer than the default 10s `wait_for` timeout. Use `kolla-ansible deploy --tags mariadb`, verify containers are healthy, then run full deploy.

3. **Inventory groups must be exhaustive** — Kolla 2025.1 validates group existence even for disabled services (`gnocchi-statsd`, `ceilometer-ipmi`). Always start from the full sample inventory and only remove what you explicitly don't need.

4. **Hostname resolution must be unique** — `prechecks` requires each hostname to resolve to exactly ONE IP (the `api_interface` IP). Disable cloud-init `manage_etc_hosts` to prevent duplicate entries from the management network.

5. **Generate Octavia certs early** — Run `kolla-ansible octavia-certificates` before prechecks. It fails without them even if Octavia isn't actively used.

6. **Create Cinder VG before prechecks** — `cinder-volumes` VG must exist on all storage/compute nodes upfront. Use loopback files for lab environments.

7. **Deploy module by module when debugging** — Use `--tags <service>` to isolate failures instead of waiting 40 min for full deploy to fail.

8. **Re-run is cheap** — Kolla-ansible is fully idempotent. When in doubt, just re-run.

9. **passlib + bcrypt 5.x incompatibility** — Kolla-ansible uses `password_hash('bcrypt')` for Prometheus web auth. passlib 1.7.4 is incompatible with bcrypt 5.x (`__about__` attribute removed, `detect_wrap_bug` fails with 72-byte limit). Fix: patch passlib's `bcrypt.py` — skip `detect_wrap_bug()` (return False) and add try/except on `__about__.__version__`. This affects Prometheus role only.

10. **Disable OVN SB DB relay for small clusters** — The relay is auto-enabled when OVN is on (`enable_ovn_sb_db_relay` defaults to `enable_ovn`). The relay container crashes due to missing `RELAY_ID` env var (kolla bug in 2025.1). For <50 node clusters, relay is unnecessary. Set `enable_ovn_sb_db_relay: "no"` in globals.yml. Do NOT use `ovn_sb_db_relay_count: 0` — it causes `range(1, 0+1)` empty sequence template error.

11. **Octavia requires physnet-oct in ML2 flat networks** — Octavia management network uses `physnet-oct` physical network. This must be:
    - Added to `[ml2_type_flat] flat_networks` in neutron ML2 config override
    - Mapped in `neutron_bridge_name` and `neutron_external_interface` globals (e.g., `br-ex,br-oct` and `ext0,oct0`)
    - The Octavia management interface (`oct0`) must exist on all controller nodes
    - Without this, deploy fails at Octavia network creation: "physical_network 'physnet-oct' unknown"

12. **Cinder HA requires `cinder_cluster_name`** — When multiple cinder-volume instances are in the inventory, `cinder_cluster_name` must be set (e.g., `"lab1cinder"`). Also set `cinder_coordination_backend: "etcd"`. Without this, prechecks fails with "Multiple cinder-volume instances detected but cinder_cluster_name is not set".

## Terraform / VM Provisioning

13. **MAC-based NIC naming is the only reliable approach** — Virtio NICs in Ubuntu cloud images get unpredictable interface names. Use MAC from `virsh domiflist` + `set-name` in netplan cloud-init config.

14. **Shell scripts > dmacvisor/libvirt Terraform provider** — Provider v0.9.2 schema is too buggy for complex multi-NIC VMs. `virt-install` + `virsh` wrapped in `null_resource` + `local-exec` is cleaner, debuggable, and well-documented.

15. **Cloud-init ISO ordering matters** — Must generate ISOs AFTER VMs exist (to read MACs from `virsh domiflist`), then attach fresh overlay disks + reboot.

16. **Provision all required NICs upfront** — Each VM needs NICs for ALL networks it participates in (mgmt, api, ext, octavia, storage, tunnel). Missing a NIC (e.g., `oct0` for Octavia) means the bridge mapping fails at deploy time. Plan all 6 networks in Terraform from the start.

## Infrastructure

17. **Audit public repos after every bootstrap** — Docker APT repo (`download.docker.com`) can sneak in via `bootstrap-servers`. Always check `/etc/apt/sources.list.d/` on all nodes after bootstrap.

18. **Nexus can't handle 5 concurrent heavy pullers** — Pre-pull images with `kolla-ansible pull` or pull node-by-node with `--limit` to avoid 503 errors from the Nexus proxy.

## Gaps Closed (IaC completeness)

All of these are now automated in `kolla-deploy.yml`:

- [x] openstack.kolla collection installed from opendev stable/2025.1
- [x] SSH key distributed to /root/.ssh/id_ed25519 for kolla root access
- [x] ansible.cfg created with collections_path, pipelining, forks
- [x] passlib patched for bcrypt 5.x before any kolla commands run
- [x] Cinder loopback uses systemd unit (not rc.local) for boot persistence
- [x] Kernel modules persisted via /etc/modules-load.d/kolla.conf
- [x] Docker daemon.json re-applied after bootstrap (in case overwritten)
- [x] Public repo audit + removal after bootstrap
- [x] Cloud-init template set to manage_etc_hosts: false from the start

## Deployment Order (Correct)

```
bootstrap-servers
  → audit public repos (remove any that snuck in)
  → octavia-certificates
  → prechecks
  → pull
  → deploy --tags mariadb (wait for Galera to stabilize)
  → deploy (full)
  → post-deploy
```

## Common Pitfalls Summary

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| "Hostname has to resolve uniquely" | Cloud-init adds mgmt IPs to /etc/hosts | Disable `manage_etc_hosts`, use API IPs only |
| "cinder-volumes VG not found" | VG not created before prechecks | Create loopback VG on all nodes first |
| "cinder_cluster_name not set" | Multiple cinder-volume hosts | Set `cinder_cluster_name` in globals |
| "group gnocchi-statsd not found" | Missing inventory groups | Use full sample inventory as base |
| MariaDB timeout during deploy | Galera bootstrap slow | Deploy MariaDB separately first |
| "password cannot be longer than 72 bytes" | passlib 1.7.4 + bcrypt 5.x bug | Patch passlib bcrypt.py |
| OVN SB relay crash / port 16641 timeout | Missing RELAY_ID env var | `enable_ovn_sb_db_relay: "no"` |
| "range empty sequence" template error | `ovn_sb_db_relay_count: 0` | Use `enable_ovn_sb_db_relay: "no"` instead |
| "physnet-oct unknown for flat provider" | Octavia physnet not in ML2 config | Add to flat_networks + bridge mappings |
| 503 from quay.cloudinative.com | Nexus overloaded by concurrent pulls | `pull` first, or use `--limit` per node |
| Public docker.com APT repo on nodes | bootstrap-servers adds it | Audit and remove after bootstrap |
| Octavia cert files missing | Certs not generated | Run `octavia-certificates` before prechecks |
