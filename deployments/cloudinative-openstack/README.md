# cloudinative-openstack — Kolla-Ansible 2026.1 (Galaxy) single-VM deploy

Build artifacts and patches for the cloudinative-openstack all-in-one deployment running on a 24-vCPU / 96 GB nested-KVM VM on the HPE DL380 Gen10 KVM host at 95.156.253.230 (`server06hiweb`).

## Layout

```
.
├── kolla/
│   ├── globals.yml          # kolla-ansible inputs (no secrets)
│   ├── inventory            # all-in-one localhost inventory
│   └── config/              # /etc/kolla/config/* custom overlays
├── docker-images/
│   └── heat-container-agent/   # patched openstackmagnum/heat-container-agent (CA-bundle baked in,
│                               # /etc/sysconfig/docker pre-created for FCOS bind mount semantics)
├── systemd-units/
│   ├── etcd-discovery-stub.service    # static etcd v2 discovery emulator (Magnum FCOS workaround)
│   ├── etcd-discovery/server.py
│   ├── openstack-br-ex-up.service     # OVN external-bridge link-up (kolla leaves it admin-down)
│   └── octavia-interface.service      # kolla's own o-hm0 dhclient unit, reproduced for reference
├── host-config/
│   ├── netplan/61-vips.yaml         # persistent internal+external HAProxy VIPs on ens3
│   └── etc-hosts.pin                # pin openstack.cloudinative.com to local VIP (escapes wildcard fallthrough)
├── branding/README.md               # Skyline + Horizon docker cp commands for the cloudinative logo + favicon
├── patches/README.md                # the eight post-deploy patches in order
├── scripts/
│   ├── vm-create.sh                 # virt-install for the openstack VM
│   ├── cloudinit-seed-build.sh      # build the seed ISO
│   └── post-deploy-bootstrap.sh     # cloudinative project, flavors, network, router, SG, keypair
├── .gitignore                       # belt-and-suspenders: blocks .pem / .key / passwords*.yml / *-openrc.sh
└── docs/
    ├── cloudinative-mirror.md       # *.cloudinative.com FQDN -> Nexus repo map (used by every layer)
    ├── operational-inventory.md     # snapshot of what's live on the deploy (instances, networks, glance, LB, k8s)
    └── magnum-capi-helm-plan.md     # production k8s-on-OpenStack path
```

## VIPs / endpoints

| Where | Address |
|---|---|
| Mgmt + nova-compute hypervisor | 95.156.253.231 (ens3) |
| Internal VIP (HAProxy) | 95.156.253.232 (ens3 secondary) |
| External VIP (HAProxy + Skyline/Horizon) | 95.156.253.235 (ens3 secondary) |
| External FQDN | openstack.cloudinative.com (TLS via *.cloudinative.com Certum DV) |
| Octavia external interface | ens4 → br-ex (OVN provider physnet1) |
| Region | cloudinative-1 |

## Reproduce from a fresh KVM host

```bash
# On the KVM host (95.156.253.230)
sudo ./scripts/cloudinit-seed-build.sh
sudo ./scripts/vm-create.sh

# After VM boots and is reachable as ubuntu@95.156.253.231
scp kolla/globals.yml ubuntu@95.156.253.231:/tmp/
scp kolla/inventory ubuntu@95.156.253.231:/tmp/
ssh ubuntu@95.156.253.231 sudo mkdir -p /etc/kolla
ssh ubuntu@95.156.253.231 sudo mv /tmp/globals.yml /etc/kolla/
ssh ubuntu@95.156.253.231 sudo mv /tmp/inventory /home/ubuntu/inventory

# Install kolla-ansible 22.0.0 (matches openstack_release=2026.1)
ssh ubuntu@95.156.253.231 'python3 -m venv ~/venv && ~/venv/bin/pip install ansible kolla-ansible==22.0.0'

# Bootstrap + deploy
ssh ubuntu@95.156.253.231 'source ~/venv/bin/activate && \
  kolla-genpwd && sudo chmod 0644 /etc/kolla/passwords.yml && \
  kolla-ansible bootstrap-servers -i ~/inventory --become && \
  kolla-ansible prechecks -i ~/inventory --become && \
  kolla-ansible deploy -i ~/inventory --become && \
  kolla-ansible post-deploy -i ~/inventory --become'

# Apply post-deploy patches (see patches/README.md), then run the bootstrap script
ssh ubuntu@95.156.253.231 ./post-deploy-bootstrap.sh
```

## Known tech debt

- **Magnum k8s_fedora_coreos_v1 driver is broken** (see patches/README.md item 6). For production tenant-self-service Kubernetes, deploy `magnum-capi-helm` instead (`docs/magnum-capi-helm-plan.md`).
- **HAProxy bound to VIPs that are not on local interfaces by default**. We add them manually as secondaries on ens3 because `enable_keepalived: no` (single-node). Persisted via `/etc/netplan/61-vips.yaml`.
- **DNS authority for cloudinative.com lives at 46.245.69.222 (bind)**, not at any registered public NS - 1.1.1.1/8.8.8.8 return SERVFAIL for the whole zone. The `openstack` A record was added there with `rndc reload` on 2026-06-15.
- **A single-VM deploy** - the production answer is multi-controller HA with separate compute nodes. globals.yml is structured to make that swap clean (no hardcoded `enable_keepalived: yes`/no, etc).

## Software versions

- Kolla-Ansible 22.0.0 (== OpenStack 2026.1 / Galaxy)
- Ubuntu 24.04.4 LTS on the VM (noble)
- libvirt 10.0 / QEMU 8.2 on KVM host
- Nested KVM enabled (Intel host-passthrough on Xeon Gold)
