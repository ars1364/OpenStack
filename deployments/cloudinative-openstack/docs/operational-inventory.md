# Operational inventory — cloudinative-openstack (2026-06-17 snapshot)

What's actually live on the deploy at the time this repo was first published. Not the full Heat/Glance/Cinder state — just the demo objects + persistent operator artifacts that anyone restoring from this repo should expect to re-create.

## Compute (Nova)

| Server | Flavor | Image | Project | IP(s) |
|---|---|---|---|---|
| cloudinative-test3 | cloudinative-small | cloudinative-ubuntu-noble | cloudinative | 10.50.0.228 / FIP 95.156.253.243 |
| cloudinative-be1 | cloudinative-tiny | cloudinative-ubuntu-noble | cloudinative | 10.50.0.251 |
| cloudinative-be2 | cloudinative-tiny | cloudinative-ubuntu-noble | cloudinative | 10.50.0.248 |
| cloudinative-k8s-cp1 | cloudinative-medium | cloudinative-ubuntu-noble | cloudinative | 10.50.0.98 / FIP 95.156.253.242 |
| amphora-<uuid> | amphora | amphora-x64-haproxy-ubuntu-noble | service (Octavia-managed) | 10.1.0.176 (lb-mgmt) + 10.50.0.152 (tenant) |

## Network (Neutron / OVN)

- **cloudinative-public** — external, flat, physnet1, subnet 95.156.253.224/27, allocation_pool .241-.243 + .246-.250 + .252, gateway .225, DNS 46.245.69.222 + 1.1.1.1
- **cloudinative-tenant** — internal, subnet 10.50.0.0/24, gateway 10.50.0.1, DNS 46.245.69.222
- **lb-mgmt-net** — Octavia-internal, subnet 10.1.0.0/24
- **cloudinative-router** — connects cloudinative-tenant to cloudinative-public, SNAT enabled, gateway IP 95.156.253.241

## Glance images (all public except amphora)

cloudinative-ubuntu-noble, cloudinative-ubuntu-jammy, cloudinative-ubuntu-focal, debian-13-cloud, almalinux-9-cloud, rocky-9-cloud, fedora-cloud-41, fedora-coreos-44, cirros-0.6.3, amphora-x64-haproxy-ubuntu-noble (private, owner=service, tag=amphora).

## Cinder

- LVM backend (volume group `cinder-volumes`, 300 GB loopback)
- No backups configured (potential future work)

## Octavia (LBaaS)

- **cloudinative-lb1** — VIP 10.50.0.214, FIP 95.156.253.252, ROUND_ROBIN HTTP :80, HM HTTP /www-index.html, members cloudinative-be1 + cloudinative-be2
- Health-manager bound on o-hm0 (10.1.0.197 currently, dhcp-leased)

## Keystone

- Domain `Default`, admin user `admin`
- Project `cloudinative` (default tenant)
- Project `service` (Octavia + Magnum trustees)
- Application credentials in use for Magnum's CAPI driver path (planned)

## Magnum

- Driver loaded: k8s_fedora_coreos_v1 only (DEPRECATED — see docs/magnum-capi-helm-plan.md)
- No active clusters as of snapshot; previous attempts deleted

## Skyline / Horizon

- Skyline UI at https://openstack.cloudinative.com:9999/ (operator confirmed login 2026-06-15)
- Horizon UI at https://openstack.cloudinative.com/ (operator confirmed login 2026-06-15)
- Region selector shows `cloudinative-1`
- Branding NOT persisted across container rebuild (see branding/README.md)

## Telemetry

- Ceilometer-compute polling libvirt every 10 minutes, publishing to gnocchi
- Gnocchi storing per-instance metrics (cpu, memory, memory.usage, memory.available, vcpus, power.state, disk.{root,ephemeral}.size, compute.instance.booting.time)
- Aodh evaluator running, no active alarms in cloudinative project (test alarm `cloudinative-test3-cpu-high` was created during verification then deleted)

## DNS

- A record `openstack.cloudinative.com -> 95.156.253.235` on bind at 46.245.69.222 (added 2026-06-15, SOA 2026061502)
- The wildcard `* IN A 46.245.69.209` still in place above the explicit record

## Kubeadm demo cluster

- Single-node k8s 1.32.5 cluster on cloudinative-k8s-cp1 (95.156.253.242:6443)
- Flannel CNI installed via raw manifest (image refs rewritten to docker.cloudinative.com/flannel/)
- Sample workloads: cloudinative-nginx + cloudinative-nginx-dep (3 replicas)
- Marked as a stop-gap demo — production answer is magnum-capi-helm

## Workers absent

- prometheus / grafana left off in globals.yml for demo VM headroom (`enable_prometheus: no`, `enable_grafana: no`)
- central_logging off
- swift not enabled
- ironic not enabled
