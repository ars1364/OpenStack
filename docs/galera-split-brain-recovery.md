# Recovering a Kolla-Ansible Galera split-brain — and the `/etc/hosts` gotcha that caused it

A real failure on a 3-controller Kolla-Ansible 2025.1 lab. Keystone returned 503,
every OpenStack API was unreachable, and the Docker `ps` output was a wall of
`(unhealthy)`. This is the full walkthrough — what we saw, how we diagnosed it,
the exact commands that brought it back, and the *actual* root cause hiding
underneath the obvious one.

If you only came for the recovery commands, jump to
[The recovery, in order](#the-recovery-in-order). If you want the story and the
why, read on.

---

## The environment

- 3 controllers: `lab-ctrl01`, `lab-ctrl02`, `lab-ctrl03`
- 2 computes: `lab-comp04`, `lab-comp05`
- Kolla-Ansible **2025.1**, MariaDB **Galera** for the OpenStack DB, RabbitMQ **4.0.9** for AMQP
- API network `192.168.204.0/24`, VIP `192.168.204.10`
- Controllers built from Ubuntu 24.04 cloud images (this part matters — see the postmortem)

---

## The symptom

Trying to source `admin-openrc.sh` and run anything:

```
$ openstack token issue
Failed to discover available identity versions when contacting
http://192.168.204.10:5000.
Could not find versioned identity endpoints when attempting to authenticate.
Please check that your auth_url is correct. Service Unavailable (HTTP 503)
```

A raw `curl` to Keystone, both via VIP and per-controller, returned 503 from
HAProxy:

```
$ curl -s -o /dev/null -w "%{http_code}\n" http://192.168.204.10:5000/v3
503

$ for i in 11 12 13; do
    code=$(curl -s -o /dev/null --connect-timeout 3 -w "%{http_code}" http://192.168.204.${i}:5000/v3)
    echo "192.168.204.${i}:5000 -> $code"
done
192.168.204.11:5000 -> 503
192.168.204.12:5000 -> 503
192.168.204.13:5000 -> 503
```

503 from HAProxy when all three backends are down means there is no live
Keystone container to send traffic to. So we went to the host.

---

## What `docker ps` said

```
$ ssh ubuntu@lab-ctrl01
$ sudo docker ps --filter health=unhealthy --format "{{.Names}}"
zun_compute
magnum_conductor
heat_engine
octavia_worker
octavia_housekeeping
octavia_health_manager
barbican_worker
barbican_keystone_listener
barbican_api
ceilometer_compute
ceilometer_central
ceilometer_notification
gnocchi_metricd
mistral_executor
mistral_event_engine
mistral_engine
neutron_server
nova_compute
nova_conductor
nova_metadata
nova_api
nova_scheduler
placement_api
cinder_volume
cinder_scheduler
cinder_api
keystone
```

Basically every service. That kind of breadth always points at the
substrate — when Keystone, Nova, Neutron, Cinder, Heat, Magnum, Octavia,
Barbican and Mistral all go unhealthy at the same time, the answer is
*always* one of: DB down, AMQP down, both. So we checked the DB first.

---

## MariaDB: looks alive, but really isn't

```
$ sudo docker ps --filter "name=mariadb" --format "table {{.Names}}\t{{.Status}}"
NAMES                STATUS
mariadb              Up 12 seconds (health: starting)
mariadb_clustercheck Up 23 hours
```

`Up 12 seconds` after a 23-hour uptime is the giveaway — the container has
been **restart-looping**. Confirmed in the docker logs:

```
$ sudo journalctl -u docker --since "2 hours ago" | grep mariadb | tail -20
... mariadb ... eid=35bca4fbc42f ...   (every ~46 seconds for the last hour)
```

So the container starts, fails health, gets restarted by Docker, and starts
again. Why? Kolla's `mariadb.log` had the answer:

```
WSREP: gcomm: connecting to group 'openstack',
   peer '192.168.204.11:4567,192.168.204.12:4567,192.168.204.13:4567'
WSREP: (c5eadb6a-8322, ...) connection established to c5f35d73-aeef tcp://192.168.204.12:4567
WSREP: (c5eadb6a-8322, ...) connection established to c5ad1e0a-b733 tcp://192.168.204.13:4567
WSREP: No nodes coming from primary view, primary view is not possible
WSREP: view(view_id(NON_PRIM,c5ad1e0a-b733,3) memb {
    c5ad1e0a-b733,0
    c5eadb6a-8322,0
    c5f35d73-aeef,0
} joined {} left {} partitioned {})
```

All three nodes can see each other on `4567`, but **no node has a primary
view** of the cluster. That is the textbook Galera split-brain after an
unclean shutdown. None of them is willing to be authoritative, so none of
them serves queries, and the OpenStack services on top — all of which
opened DB connections that now `Lost connection to MySQL server during
query` — pile up errors until their oslo.db retry budget is exhausted:

```
... -8289 attempts left ...
... -8290 attempts left ...
```

Negative numbers mean they gave up a long time ago and are now just looping
on the dead connection. At this point the services are zombies — they
won't recover even after we fix the DB. Remember that; we'll come back to
it.

### What's in `grastate.dat`?

Each node has a `grastate.dat` file inside the mariadb volume that records
the last known committed seqno and whether this node is safe to bootstrap
from. After we cleanly stopped mariadb on all three:

```
$ for ip in 11 12 13; do
    echo "--- 192.168.204.$ip ---"
    sudo ssh ubuntu@192.168.204.$ip \
      'sudo cat /var/lib/docker/volumes/mariadb/_data/grastate.dat'
done

--- 192.168.204.11 ---
seqno: -1
safe_to_bootstrap: 1

--- 192.168.204.12 ---
seqno: -1
safe_to_bootstrap: 0

--- 192.168.204.13 ---
seqno: -1
safe_to_bootstrap: 0
```

`seqno: -1` everywhere means none of them shut down cleanly — mariadb only
writes the actual seqno into grastate on a clean stop, and these containers
were killed in the middle of the split-brain. We need `wsrep_recover` to
read the real position out of the InnoDB redo log.

This is exactly the situation that `kolla-ansible mariadb-recovery` is
designed to handle. It runs `mysqld --wsrep-recover` on every node, picks
the one with the highest seqno, sets `safe_to_bootstrap: 1` on it, starts
that one as a new primary with `--wsrep-new-cluster`, then rolls the others
in as joiners.

---

## The recovery, in order

### 0. Pre-flight

You need:

- SSH (with key auth, no prompts) to every MariaDB node as a user that can
  `sudo` without a password
- The Kolla inventory file (`/etc/kolla/multinode` for us)
- The Kolla passwords file (`/etc/kolla/passwords.yml`)
- The Kolla venv with `kolla-ansible` installed (`/opt/kolla-venv/bin/kolla-ansible` for us)

The kolla user/key the inventory will use is set in `/etc/kolla/ansible.cfg`:

```ini
[defaults]
host_key_checking = False
private_key_file = /root/.ssh/id_ed25519
```

If `ansible_user` isn't set per-host, it defaults to the user running ansible
(root via sudo). Make sure that key is in `authorized_keys` on every node for
that user.

### 1. Stop MariaDB on all three controllers

```bash
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} 'sudo docker stop mariadb'
done
```

Verify all are stopped — you should see `Exited (0)` on each:

```bash
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} \
    'sudo docker ps -a --filter name=^mariadb$ --format "{{.Names}} {{.Status}}"'
done
```

### 2. Run `kolla-ansible mariadb-recovery`

This is the canonical Kolla way. It handles seqno discovery, bootstrap
selection, and the joiner rejoin in one shot.

There is a known wart: kolla-ansible's filter plugins import the
`kolla_ansible` Python module from the venv, and ansible's subprocess
doesn't always pick that path up. If you see

```
template error while templating string: Could not load
"select_services_enabled_and_mapped_to_host": 'select_services_enabled_and_mapped_to_host'.
```

fix it by setting `PYTHONPATH` and `ANSIBLE_PYTHON_INTERPRETER` explicitly:

```bash
sudo env PYTHONPATH=/opt/kolla-venv/lib/python3.12/site-packages \
       ANSIBLE_PYTHON_INTERPRETER=/opt/kolla-venv/bin/python \
  /opt/kolla-venv/bin/kolla-ansible mariadb-recovery \
  -i /etc/kolla/multinode \
  --passwords /etc/kolla/passwords.yml \
  --configdir /etc/kolla
```

This took ~3 minutes on our 3-node cluster. The play recap should end with
zero failures:

```
PLAY RECAP *********************************************************************
lab-ctrl01  : ok=35  changed=6  unreachable=0  failed=0  ...
lab-ctrl02  : ok=25  changed=3  unreachable=0  failed=0  ...
lab-ctrl03  : ok=25  changed=3  unreachable=0  failed=0  ...
```

The final task in the play is `Wait for MariaDB service to be ready
through VIP` — when that's `ok` on all three, the VIP is serving queries
again.

### 3. Verify Galera cluster state

```bash
DB_PW=$(sudo grep ^database_password /etc/kolla/passwords.yml | awk '{print $2}')
sudo docker exec mariadb mariadb -uroot -p"$DB_PW" -e "
  SHOW STATUS LIKE 'wsrep_cluster_size';
  SHOW STATUS LIKE 'wsrep_local_state_comment';
  SHOW STATUS LIKE 'wsrep_ready';
  SHOW STATUS LIKE 'wsrep_cluster_status';"
```

You want to see `wsrep_cluster_size=3`, `wsrep_local_state_comment=Synced`,
`wsrep_ready=ON`, `wsrep_cluster_status=Primary`.

### 4. Confirm Keystone is reachable

```bash
for url in http://192.168.204.10:5000/v3 \
           http://192.168.204.11:5000/v3 \
           http://192.168.204.12:5000/v3 \
           http://192.168.204.13:5000/v3; do
  printf "%s -> %s\n" "$url" "$(curl -s -o /dev/null --connect-timeout 5 -w '%{http_code}' $url)"
done
```

All four should be `200`. If the VIP is `200` but per-controller is mixed,
HAProxy is still draining stale backends — give it 30 seconds.

---

## "The DB is back, why is everything still broken?"

This is the part nobody puts in their runbook. After `mariadb-recovery`
finished and Keystone returned 200, we ran:

```bash
$ openstack endpoint list --interface public
... 16 endpoints, all populated ...

$ openstack compute service list
nova-scheduler   lab-ctrl01   down
nova-scheduler   lab-ctrl02   down
nova-scheduler   lab-ctrl03   down
nova-conductor   lab-ctrl01   down
...
```

Everything was listed in the catalog but reporting **down**. The container
healthchecks were still unhealthy. As predicted earlier, the services had
exhausted their retry budget on the *old* DB connections during the outage,
so they wouldn't reconnect on their own. The fix is to restart them so they
re-establish fresh DB + AMQP sessions:

```bash
SVCS="nova_api nova_metadata nova_conductor nova_scheduler nova_compute \
      neutron_server placement_api \
      cinder_api cinder_scheduler cinder_volume \
      heat_api heat_engine \
      magnum_api magnum_conductor \
      octavia_api octavia_worker octavia_health_manager octavia_housekeeping \
      barbican_api barbican_worker barbican_keystone_listener \
      mistral_api mistral_engine mistral_event_engine mistral_executor \
      zun_api zun_compute \
      ceilometer_central ceilometer_compute ceilometer_notification \
      gnocchi_metricd gnocchi_api \
      glance_api keystone"

for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} "
    for s in $SVCS; do
      sudo docker restart -t 8 \$s 2>/dev/null
    done
  "
done
```

`-t 8` gives each process eight seconds to drain before SIGKILL, which is
plenty for these stateless API workers. The whole loop takes about a minute
per node.

Wait 60-90 seconds and re-check `compute service list`. If services are
still down, **read the logs before restarting again** — there is probably
something else broken underneath. In our case there was.

---

## The real root cause: cloud-init wiped `/etc/hosts` on reboot

When we restarted the services, they all started spamming:

```
ERROR oslo.messaging._drivers.impl_rabbit Connection failed:
   [Errno 111] ECONNREFUSED (retrying in 0 seconds)
```

RabbitMQ was down. On `lab-ctrl01`:

```
$ sudo docker ps -a --filter name=^rabbitmq$ --format "{{.Names}} {{.Status}}"
rabbitmq    Exited (1) 8 seconds ago
```

The rabbit log was clear:

```
[error] Application rabbitmq_prelaunch exited with reason:
   {{shutdown,{failed_to_start_child,prelaunch,
       {epmd_error,"lab-ctrl01",address}}}, ...}
Kernel pid terminated (application_controller)
```

`epmd_error,"lab-ctrl01",address` means Erlang's port mapper daemon
couldn't resolve the node's *own* hostname. Which means `/etc/hosts` was
broken. Sure enough:

```
$ sudo cat /etc/hosts
# Your system has configured 'manage_etc_hosts' as True.
# ...
127.0.1.1 lab-ctrl01.lab.local lab-ctrl01
127.0.0.1 localhost

::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
```

**No cluster peer entries at all.** Just the local node — and it's mapped
to `127.0.1.1`, which means even when peers exist locally, every node thinks
its own hostname is loopback. RabbitMQ binds to `192.168.204.11:5672` per
its config, but its cluster config references `rabbit@lab-ctrl01`, and
Erlang resolves that to `127.0.1.1`, so peers can't reach it.

The reason `/etc/hosts` is bare? **`manage_etc_hosts: True` in cloud-init.**
On every boot, cloud-init regenerates `/etc/hosts` from
`/etc/cloud/templates/hosts.debian.tmpl`, which only includes the local
host. Anything Kolla wrote during deployment — gone. The cluster had been
rebooted ~23 hours ago. From that moment on, RabbitMQ was unable to start
on any node, OpenStack services lost their AMQP connections, MariaDB started
seeing wedged client sessions, and eventually Galera dropped to NON_PRIM.

Galera was the visible symptom. cloud-init was the cause.

### The fix

On every controller:

```bash
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} '
    # 1. Disable cloud-init management of /etc/hosts on next boot
    sudo sed -i "s/^manage_etc_hosts: true/manage_etc_hosts: false/" \
      /etc/cloud/cloud.cfg
    grep -q "manage_etc_hosts: false" /etc/cloud/cloud.cfg || \
      echo "manage_etc_hosts: false" | sudo tee -a /etc/cloud/cloud.cfg >/dev/null

    # 2. Add cluster hosts (real IPs, not loopback)
    if ! grep -q "192.168.204.11 lab-ctrl01" /etc/hosts; then
      sudo tee -a /etc/hosts <<EOF
# kolla cluster hosts
192.168.204.11 lab-ctrl01
192.168.204.12 lab-ctrl02
192.168.204.13 lab-ctrl03
192.168.204.14 lab-comp04
192.168.204.15 lab-comp05
EOF
    fi

    # 3. Comment out the 127.0.1.1 hostname line — order matters in
    # /etc/hosts and we do NOT want our own hostname resolving to loopback
    sudo sed -i "/^127\.0\.1\.1 lab-ctrl0/s/^/#/" /etc/hosts
  '
done
```

Then verify each node resolves its own hostname to the real IP, not
loopback:

```bash
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} 'getent hosts $(hostname)'
done
```

You should see `192.168.204.{11,12,13}` — never `127.0.1.1`.

### Restart RabbitMQ and verify

```bash
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} 'sudo docker start rabbitmq'
done
sleep 60
sudo docker exec rabbitmq rabbitmqctl cluster_status
```

You want:

```
Disk Nodes
   rabbit@lab-ctrl01
   rabbit@lab-ctrl02
   rabbit@lab-ctrl03

Running Nodes
   rabbit@lab-ctrl01
   rabbit@lab-ctrl02
   rabbit@lab-ctrl03

Network Partitions
   (none)

Alarms
   (none)
```

Three running nodes, no partitions, no alarms. Now restart all the
OpenStack services one more time (same `$SVCS` loop as before) so they
re-establish AMQP from a healthy cluster, and verify:

```bash
$ openstack compute service list -f value -c Binary -c Host -c State
nova-scheduler  lab-ctrl01  up
nova-scheduler  lab-ctrl02  up
nova-scheduler  lab-ctrl03  up
nova-conductor  lab-ctrl01  up
nova-conductor  lab-ctrl02  up
nova-conductor  lab-ctrl03  up
...

$ openstack coe service list           # Magnum / KaaS
| 1 | 192.168.204.11 | magnum-conductor | up |
| 4 | 192.168.204.12 | magnum-conductor | up |
| 7 | 192.168.204.13 | magnum-conductor | up |

$ openstack appcontainer service list  # Zun / CaaS
|  1 | lab-ctrl01 | zun-compute | up |
|  4 | lab-ctrl02 | zun-compute | up |
|  7 | lab-ctrl03 | zun-compute | up |

$ openstack volume service list        # Cinder
| cinder-scheduler  | lab-ctrl01  | up |
| cinder-scheduler  | lab-ctrl02  | up |
| cinder-scheduler  | lab-ctrl03  | up |
| cinder-volume     | lab-ctrl01  | up |
| cinder-volume     | lab-ctrl02  | up |
| cinder-volume     | lab-ctrl03  | up |
```

Cluster recovered.

---

## Postmortem notes

- The visible failure was Galera. The actual root cause was cloud-init
  silently wiping `/etc/hosts`. Recovering Galera without fixing
  `manage_etc_hosts` would have left a time bomb — the next reboot would
  put us right back here.
- `manage_etc_hosts: True` is the default on Ubuntu Cloud Images. If you
  use those images as the base for your OpenStack controllers and you let
  Kolla put cluster entries into `/etc/hosts`, you must disable cloud-init's
  managed-hosts mode during deployment. Otherwise it works exactly until
  the first reboot and then it doesn't.
- A two-line entry in your Kolla deploy playbook (or a cloud-init `write_files`
  block) saves you from this. So does using a DNS server, but DNS adds its
  own failure mode — host-file entries are stupid and reliable, as long as
  cloud-init isn't fighting you.
- After any DB outage longer than the oslo.db retry budget (~5 minutes
  on default settings, less in practice once attempts decay), OpenStack
  services will not self-heal. You **must** restart them. Don't trust the
  service catalog being populated as evidence that things work — check
  `service list` per project and look at `Updated At` timestamps.
- `mariadb_clustercheck` reporting `Up 23 hours` while `mariadb` is
  restart-looping is misleading. The clustercheck container's "Up" time
  reflects when *its own* process started, not the health of the cluster
  it's checking. Always look at the actual mariadb container's status and
  log, not the clustercheck sidecar.
- During the recovery, the `kolla-ansible mariadb-recovery` playbook
  picked `lab-ctrl01` because that was the only node with
  `safe_to_bootstrap: 1`. If `safe_to_bootstrap` is 0 everywhere — which
  it will be after a full hard-power-off — you'll need to run
  `wsrep_recover` manually on each node, find the highest seqno, and edit
  `safe_to_bootstrap: 1` on the winner before invoking the playbook.

---

## Quick reference: full recovery in one block

```bash
# 1. Stop mariadb everywhere
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} 'sudo docker stop mariadb'
done

# 2. Run the kolla recovery playbook
sudo env PYTHONPATH=/opt/kolla-venv/lib/python3.12/site-packages \
       ANSIBLE_PYTHON_INTERPRETER=/opt/kolla-venv/bin/python \
  /opt/kolla-venv/bin/kolla-ansible mariadb-recovery \
  -i /etc/kolla/multinode \
  --passwords /etc/kolla/passwords.yml \
  --configdir /etc/kolla

# 3. Repair /etc/hosts on every controller and disable cloud-init mgmt
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} '
    sudo sed -i "s/^manage_etc_hosts: true/manage_etc_hosts: false/" /etc/cloud/cloud.cfg
    grep -q "192.168.204.11 lab-ctrl01" /etc/hosts || sudo tee -a /etc/hosts <<EOF
192.168.204.11 lab-ctrl01
192.168.204.12 lab-ctrl02
192.168.204.13 lab-ctrl03
192.168.204.14 lab-comp04
192.168.204.15 lab-comp05
EOF
    sudo sed -i "/^127\.0\.1\.1 lab-ctrl0/s/^/#/" /etc/hosts
  '
done

# 4. Restart RabbitMQ
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} 'sudo docker start rabbitmq'
done
sleep 60

# 5. Restart all OpenStack containers so they re-establish AMQP/DB
SVCS="nova_api nova_metadata nova_conductor nova_scheduler nova_compute \
      neutron_server placement_api cinder_api cinder_scheduler cinder_volume \
      heat_api heat_engine magnum_api magnum_conductor \
      octavia_api octavia_worker octavia_health_manager octavia_housekeeping \
      barbican_api barbican_worker barbican_keystone_listener \
      mistral_api mistral_engine mistral_event_engine mistral_executor \
      zun_api zun_compute glance_api keystone"
for ip in 11 12 13; do
  sudo ssh ubuntu@192.168.204.${ip} "for s in $SVCS; do sudo docker restart -t 8 \$s 2>/dev/null; done"
done

# 6. Verify
source /etc/kolla/admin-openrc.sh
openstack endpoint list --interface public
openstack compute service list
openstack coe service list           # KaaS / Magnum
openstack appcontainer service list  # CaaS / Zun
openstack volume service list        # Cinder
```

That's the whole thing. Total wall-clock time on our lab: about 12
minutes, of which 3 were the playbook itself.
