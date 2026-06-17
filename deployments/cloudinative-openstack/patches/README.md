# Post-deploy patches for cloudinative-openstack

The kolla-ansible 2026.1 install runs cleanly with the globals.yml in `../kolla/globals.yml`, but a number of issues need fixing on the running deployment **after** `kolla-ansible deploy` exits 0. Apply these in order.

## 0. cluster-cidr expansion (only if you hit "no FIPs available")

The /27 (`95.156.253.224/27`) has 9 addresses in the FIP pool. When deleting/recreating clusters, orphan FIPs accumulate. Release unattached FIPs:

```bash
. /tmp/admin-openrc.sh
openstack floating ip list -f value -c ID -c "Fixed IP Address" | awk '$2=="None"{print $1}' | xargs -I X openstack floating ip delete X
```

## 1. octavia certs - host bind/perm fix

After `kolla-ansible deploy` octavia-certificates phase, the .pem files get mode 0600 root:root. kolla-ansible's `ansible.builtin.copy` on the next deploy reads them as the connecting user (here `ubuntu`), not root, even with `--become`:

```bash
sudo chmod -R go+rX /etc/kolla/config /etc/kolla/octavia-certificates /etc/kolla/certificates
```

## 2. dev/shm/openstack_uwsgi_qmanager collision (Kolla 2026.1)

oslo_messaging derives its shm filename from `hostname + processname`, and every uwsgi-wrapped openstack service has processname="uwsgi", so they all collide on `/dev/shm/openstack_uwsgi_qmanager` and break each other's RPC reply tracking. Disable the qmanager optimization for any service that needs RPC (magnum-api, nova-api etc):

```ini
# In e.g. /etc/kolla/magnum-api/magnum.conf and /etc/kolla/magnum-conductor/magnum.conf
[oslo_messaging_rabbit]
use_queue_manager = false
```

(See `scripts/post-deploy-bootstrap.sh` for the sed expression and the container restart.)

## 3. magnum cluster_user_trust (default off in 2026.1)

```ini
# In /etc/kolla/magnum-{api,conductor}/magnum.conf
[trust]
cluster_user_trust = True
```

Without it, the master VM gets TRUST_ID="" in /etc/sysconfig/heat-params, the bootstrap scripts ask keystone for a trust-scoped token with empty id, the call returns empty, no cert chain.

## 4. octavia health-manager bind to lb-mgmt-net (was binding to public api IP)

```ini
# In /etc/kolla/octavia-{health-manager,worker,housekeeping,api,driver-agent}/octavia.conf
[health_manager]
bind_ip = 10.1.0.207     # the o-hm0 IP - read from /etc/octavia-interface
controller_ip_port_list = 10.1.0.207:5555
```

(Set this BEFORE running `kolla-ansible reconfigure --tags octavia` if you want it to stick across reconfigures - but reconfigure resets the conf each time. The safest path is to set `octavia_network_type: tenant` in globals.yml and let the kolla-ansible hm-interface.yml task derive these correctly.)

## 5. cloudinative project default SG rules

The auto-created default security group in the cloudinative project only allows traffic from same SG. For demo workloads add public ingress:

```bash
. /tmp/admin-openrc.sh
sg=$(openstack security group list --project cloudinative -f value | grep '^[a-f0-9]\{36\}.*\sdefault\s' | awk '{print $1}')
for spec in icmp tcp:22 tcp:80 tcp:443 tcp:6443; do
  proto="${spec%:*}"; port="${spec#*:}"
  if [ "$proto" = "icmp" ]; then
    openstack security group rule create --proto icmp --ingress --remote-ip 0.0.0.0/0 $sg
  else
    openstack security group rule create --proto $proto --dst-port $port --ingress --remote-ip 0.0.0.0/0 $sg
  fi
done
```

## 6. magnum FCOS heat driver (DEPRECATED)

The `k8s_fedora_coreos_v1` driver in Magnum 2026.1 is effectively dead - 5-year-old image set, broken upstream tags (hyperkube:v1.23.3-rancher1 missing on docker.io, openstackmagnum/etcd:v3.4.6 missing). Documented patches we built to get partway through it are in `docker-images/heat-container-agent/` (CA-bundle install wrap) and `systemd-units/etcd-discovery-stub.service` (etcd v2 discovery stub) - keep them as artifacts but the right answer for production is the `magnum-capi-helm` driver. See `docs/magnum-capi-helm-plan.md`.

## 7. cloudinative.com authoritative DNS

The Nexus mirror chain depends on the bind zone db at 46.245.69.222 (`db.cloudinative.com`). For openstack.cloudinative.com to resolve to 95.156.253.235 (the external VIP), add:

```
openstack	IN	A	95.156.253.235
```

above the wildcard `*  IN  A  46.245.69.209` line. Bump the SOA serial, `rndc reload cloudinative.com`.

## 8. host-side network plumbing

The OpenStack VM needs two L2-bridged NICs (publicnet over br0 on the KVM host). After kolla deploy, manually:

- Add the internal+external VIPs as secondary addresses on ens3 (so HAProxy's `bind` actually has a route back from the same host):

```bash
sudo ip addr add 95.156.253.232/27 dev ens3
sudo ip addr add 95.156.253.235/27 dev ens3
# Persist via /etc/netplan/61-vips.yaml
```

- Pin `openstack.cloudinative.com` to 95.156.253.235 in `/etc/hosts` so Skyline's container (which uses systemd-resolved that DOES NOT see the cloudinative DNS by default) reaches the local VIP, not the external 46.245.69.209 fallback.

- Bring up `br-ex` (OVS internal port, plumbed onto br-int by the openvswitch container at deploy time; left admin-down by kolla). Systemd unit at `../systemd-units/openstack-br-ex-up.service`.

- Bring up `o-hm0` (Octavia health-manager interface, runs kolla's `octavia-interface.service` which dhclients the lb-mgmt-net). Confirm port exists in Neutron and OVS iface external-ids match.
