# Build journal — every issue hit during the cloudinative-openstack bring-up

This documents the real path the deploy took 2026-06-14 through 2026-06-17, not the idealized "ran one command, done" version. Every issue listed here either has a fix already captured elsewhere in this tree (referenced) or was a transient/external problem the operator should know about. **Read this top to bottom if you're rebuilding from a fresh VM** — the order is roughly the order things break in.

## Phase 0 — VM + cloud-init seed

| Issue | Fix |
|---|---|
| Initial cloud-init `apt:` module overrides `write_files`-supplied `/etc/apt/sources.list.d/ubuntu.sources` on Ubuntu (yum_repos does stick on AlmaLinux but apt doesn't). | Use cloud-init's native `apt:` directive for `primary` + `security` mirror; don't rely on `write_files` to win. (Reflected in `scripts/cloudinit-seed-build.sh`.) |
| The Ubuntu noble images on Glance ship 6.8 kernel; nested KVM works only after `modprobe kvm_intel nested=1` on the KVM host AND `--cpu host-passthrough,migratable=on` in `virt-install`. | `scripts/vm-create.sh` sets both. Host needs `/etc/modules-load.d/kvm-nested.conf` already in place. |

## Phase 1 — Pre-kolla on the VM

| Issue | Fix |
|---|---|
| `apt update` defaults to `nova.clouds.archive.ubuntu.com` which is unreachable from this network. | Rewrite to `apt.cloudinative.com` in `/etc/apt/sources.list.d/ubuntu.sources` (cloud-init seed in `scripts/cloudinit-seed-build.sh` sets `apt.primary.uri`). |
| `download.docker.com` for docker-ce GPG key + repo is unreachable. | Use distro's `docker.io` apt package instead — set `enable_docker_repo: "no"` + `docker_apt_package: "docker.io"` in globals.yml. After install, `systemctl unmask docker && systemctl restart docker`. |
| `pip install kolla-ansible` reaches pypi.org by default — unreachable. | Use `pip install -i https://pypi.cloudinative.com/simple/ kolla-ansible==22.0.0` (matches 2026.1). |
| `opendev.org/openstack/...` (kolla-ansible source repos for ansible-galaxy collection build) is unreachable. | Cloned each needed repo on dev05 via SOCKS5 (`tg://socks?server=95.156.253.251&port=1080&user=H9QOJstvDj2ysx&pass=tElDUVhQHjWkUc`), tarred, scp'd into the VM. |
| `ansible-galaxy collection install` hits galaxy.ansible.com — unreachable. | Bundle the system-installed collections from dev05 (`/usr/lib/python3/dist-packages/ansible_collections`, 68 MB tar), scp to VM, untar to `/usr/share/ansible/collections`. Then `--force` install the openstack.kolla collection from the locally-cloned source tarball. |

## Phase 2 — bootstrap-servers + prechecks

| Issue | Fix |
|---|---|
| `kolla-ansible -i ~/inventory --become bootstrap-servers` fails: "option must come after the action name". | CLI syntax changed in kolla-ansible 22 — use `kolla-ansible bootstrap-servers -i ~/inventory --become` (action first, then opts). |
| `prechecks` errors: "No host matched the play targeting baremetal" — the inventory had `[control] localhost ansible_connection=local` but only in `[control]`. | Replace with the reference all-in-one inventory that puts `localhost ansible_connection=local` in every group: control / network / compute / storage / monitoring / deployment. (See `kolla/inventory`.) |
| `prechecks` errors: empty passwords.yml. | `~/venv/bin/kolla-genpwd` (kolla-genpwd is in the venv, not on PATH by default). |
| `prechecks` errors: "Permission denied on /etc/kolla/passwords.yml". | `sudo chmod 644 /etc/kolla/passwords.yml /etc/kolla/globals.yml`. |
| `prechecks` errors: `ModuleNotFoundError: No module named 'docker'`. | `sudo pip install --break-system-packages -i https://pypi.cloudinative.com/simple/ docker` — installs system-wide so the ansible `become=true` task sees it (kolla-ansible runs as root for some tasks via the host's /usr/bin/python3, not the venv). |
| `prechecks` errors: `ModuleNotFoundError: No module named 'dbus'`. | `sudo apt install -y python3-dbus libdbus-1-dev libglib2.0-dev pkg-config` then `sudo pip install --break-system-packages -i https://pypi.cloudinative.com/simple/ dbus-python`. |
| `prechecks` errors: "neutron_dns_domain must end with '.'". | `neutron_dns_domain: "cloudinative.com."` in globals.yml (trailing period mandatory). |
| `prechecks` errors: "Valkey must be enabled when using Octavia Jobboard". | `enable_valkey: "yes"` in globals.yml. |

## Phase 3 — deploy

| Issue | Fix |
|---|---|
| Loadbalancer play fails copying `/etc/kolla/certificates/haproxy.pem`: permission denied. The Certum cert + key + chain combined into haproxy.pem is mode 0600 root:root, but `ansible.builtin.copy` reads the SRC on the ansible controller as the connection user (ubuntu), not the become user. | `sudo chmod 0644 /etc/kolla/certificates/haproxy.pem; sudo chmod 0755 /etc/kolla/certificates`. Same pattern for octavia certs (`/etc/kolla/octavia-certificates/`). Or: `sudo -E env PATH=... kolla-ansible deploy` so the controller runs as root. We use the latter on subsequent runs. |
| MariaDB post-config: `Can't connect to MySQL server on '95.156.253.232' ([Errno 113] No route to host)`. HAProxy binds to .232 + .235 via `net.ipv4.ip_nonlocal_bind=1`, but the VM's only interface (ens3) has just .231, so kernel routes 232/235 packets out the default gateway. | Add VIPs as ens3 secondaries: `sudo ip addr add 95.156.253.232/27 dev ens3; sudo ip addr add 95.156.253.235/27 dev ens3`. Persist via `host-config/netplan/61-vips.yaml`. |
| Keystone image pull errors mid-deploy: `failed to copy: httpReadSeeker: failed open: ... EOF`. Nexus quay-proxy sometimes drops the connection during a blob fetch. | Manual `docker pull docker-quay.cloudinative.com/openstack.kolla/keystone:2026.1-ubuntu-noble` succeeds on retry. Defensive: pre-pull all ~50 openstack-images BEFORE `kolla-ansible deploy` so the deploy is a cache hit. (See `scripts/pre-pull-kolla-images.sh` if/when added.) |
| Nova-cell play errors: `Error connecting: ... Not supported URL scheme http+docker`. docker SDK 5.0.3 (Ubuntu noble's default `python3-docker`) plus urllib3 2.0.7 (debian-managed) is incompatible with newer requests; the legacy `http+docker:` transport handler breaks. | `sudo pip install --break-system-packages -i https://pypi.cloudinative.com/simple/ "docker>=7.1.0"`. Then `sudo pip install --break-system-packages --ignore-installed -i https://pypi.cloudinative.com/simple/ "urllib3<2"` if you still see the issue (the urllib3 downgrade is the belt-and-suspenders). |
| Same error reappears after docker SDK upgrade: kolla-ansible uses `community.docker.docker_image_info` which has its OWN embedded copy of docker-py. The bundled copy in community.docker 3.7.0 (kolla 2026.1 default) is still broken. | Upgrade the collection: download `community-docker-5.2.1.tar.gz` via SOCKS5 on dev05 from galaxy.ansible.com, scp to VM, `sudo ansible-galaxy collection install /tmp/community-docker-5.2.1.tar.gz -p /usr/share/ansible/collections --force`. |
| octavia config-copy step errors: "Could not find or access /etc/kolla/config/octavia/server_ca.key.pem". Same pattern as the haproxy.pem issue — kolla-ansible's copy task can't read 0600 root files when running as `ubuntu`. | `sudo chmod -R go+rX /etc/kolla/config /etc/kolla/octavia-certificates /etc/kolla/certificates` after `kolla-ansible octavia-certificates`. |
| After successful deploy, `/dev/shm/openstack_uwsgi_qmanager` is owned by whichever uwsgi-wrapped service started first (cinder-api, nova-api, magnum-api, designate-* etc all use processname="uwsgi" and collide on this one filename). magnum-api can't write it -> RPC reply queue tracking dies -> magnum-conductor calls return MessagingTimeout -> 502 to clients. | Disable the qmanager optimization for any service that hits this: `[oslo_messaging_rabbit] use_queue_manager = false` in `/etc/kolla/magnum-api/magnum.conf` and `/etc/kolla/magnum-conductor/magnum.conf`, restart both containers. (See `patches/README.md` item 2.) |
| Magnum cluster creates fail because masters get TRUST_ID="" in heat-params. | Default `[trust] cluster_user_trust=False` in 2026.1 — change to True in magnum-api + magnum-conductor confs. (See `patches/README.md` item 3.) |
| Octavia health-manager binds to 95.156.253.231 (the api_interface IP) but amphorae are on lb-mgmt-net (10.1.0.0/24) with no route there. | `octavia_network_type: tenant` in globals.yml (default is `provider`, which assumes lb-mgmt is a flat provider network on api_interface). With `tenant`, kolla-ansible's hm-interface.yml task creates a neutron port on lb-mgmt-net, plugs `o-hm0` on br-int with the right external-ids/MAC, installs the `octavia-interface.service` systemd unit (dhclient-driven). bind_ip and controller_ip_port_list then point at the o-hm0 IP. (See `patches/README.md` item 4 + `systemd-units/octavia-interface.service`.) |
| `octavia-interface.service` 203/EXEC because `/sbin/dhclient` symlink loops back on itself (apt.cloudinative.com failed mid-install, leaving a broken symlink). | `sudo apt-get install -y --reinstall isc-dhcp-client`. If apt.cloudinative.com is also down, scp the .deb from dev05 (downloaded via SOCKS5 from archive.ubuntu.com): `isc-dhcp-common_4.4.3-P1-4ubuntu2_amd64.deb` + `isc-dhcp-client_4.4.3-P1-4ubuntu2_amd64.deb`, then `sudo dpkg -i`. |
| `br-ex` (OVN external bridge) is admin-down after deploy. OVN creates the OVS internal port but never `ip link set up`. FIPs can't egress through it. | `systemd-units/openstack-br-ex-up.service` brings it up at boot. |

## Phase 4 — post-deploy bootstrap (cloudinative project, flavors, network)

| Issue | Fix |
|---|---|
| Default Neutron SG on a new project only allows traffic from same SG (the auto-created `default` group has `ingress` from group, not from world). Means LB members are unreachable from amphora, ssh from outside fails. | Add explicit ingress rules for icmp + tcp/22 + tcp/80 + tcp/443 + tcp/6443. (See `scripts/post-deploy-bootstrap.sh` and `patches/README.md` item 5.) |
| Glance image upload via curl from SOCKS5 — Ubuntu cloud image download truncated (got 585 MB, expected 599 MB). qcow2 internally corrupt → nova-compute fails `qemu-img convert -O raw`. | Always verify sha256 after SOCKS5 download. The fetch loop: `curl --retry 10 --retry-all-errors --continue-at - ... && [ "$(stat -c%s $f)" = "$EXPECTED_SIZE" ] && [ "$(sha256sum $f | awk '{print $1}')" = "$EXPECTED_SHA" ]`. Applied to: noble.img, jammy.img, focal.img, alma9, debian13, fedora41, rocky9, fcos44, amphora. |
| Amphora image `qemu-img check` reports 1470 internal qcow2 errors after first download (size 403 MB vs expected 383 MB). Octavia LB creation fails. | Re-download with proper retry — only complete OR full-restart, no append-on-resume. `qemu-img check` is the canary. |
| FIP pool exhaustion on the /27 (9 usable IPs). Magnum cluster create fails on extrouter port. | Release orphan FIPs (`openstack floating ip list -f value | awk '$2=="None"{print $1}' | xargs -I X openstack floating ip delete X`), detach FIPs from backends that the LB reaches over tenant-net anyway. |

## Phase 5 — Magnum FCOS attempts (don't repeat this — go straight to magnum-capi-helm)

We spent ~6 hours trying to make k8s_fedora_coreos_v1 work and never got a Ready node. The bugs in order, all listed for archeological value:

1. discovery.etcd.io is unreachable → wrote an etcd v2 discovery emulator (`systemd-units/etcd-discovery-stub.service` + `systemd-units/etcd-discovery/server.py`).
2. heat-container-agent image is 5 years old, ships a broken ca-bundle.crt symlink, can't TLS to https://openstack.cloudinative.com:5000. → Built `docker-images/heat-container-agent/Dockerfile` (cloudinative-4 tag) that patches `/usr/bin/start-heat-container-agent` to install a real bundle from `/opt/ca-bundle-cloudinative.crt` on first start.
3. Default `kube_tag=v1.23.3-rancher1` doesn't exist anywhere on docker.io. → Tried `v1.20.3-cern.0` (the CERN fork). Worked partway.
4. `openstackmagnum/etcd:v3.4.6` doesn't exist on docker.io either. → `docker pull docker.cloudinative.com/coreos/etcd:v3.4.6` (via quay-proxy) + retag + push to `registry.cloudinative.com/openstackmagnum/etcd:v3.4.6`. Added `docker-private` as a member of `docker-group` so the group endpoint resolves it.
5. `openstackmagnum/flannel-cni-plugin:v0.3.0` doesn't exist anywhere. → No workaround found. This is where we stopped.
6. Even after manual etcd start, kubelet panics in `pkg/kubelet/dockershim/network/cni/cni.go` because `/opt/cni/bin` is empty. flannel install scripts depend on `kubectl apply -f` against the apiserver, but apiserver doesn't come up without kubelet, which doesn't come up without CNI. Classic chicken-and-egg.
7. All of which is why the migration plan is `docs/magnum-capi-helm-plan.md`.

## Phase 6 — kubeadm demo cluster (the working k8s path)

| Issue | Fix |
|---|---|
| Cloudinative apt repo `apt.cloudinative.com/kubernetes/...` returns 502 (Nexus can't reach pkgs.k8s.io upstream). | Download `kubeadm` + `kubelet` + `kubectl` binaries directly from `dl.k8s.io` via SOCKS5 on dev05. Verify sha256 against `https://dl.k8s.io/release/v1.32.5/bin/linux/amd64/<bin>.sha256`. scp to VM. |
| SOCKS5 truncated the kubeadm binary on first try (sha256 mismatch). | Retry loop with sha256 verify after each attempt. |
| containerd's default config doesn't set `sandbox_image` and uses an outdated default. kubelet pulls pause via crio fallback path then panics. | Regenerate `/etc/containerd/config.toml` via `containerd config default`, then `sed` `SystemdCgroup = false` → `true` and `sandbox = '...pause:3.10.1'` → `sandbox = 'k8s.cloudinative.com/pause:3.10'`. Add `/etc/containerd/certs.d/<host>/hosts.toml` overlays for docker.io / quay.io / registry.k8s.io / gcr.io pointing at the cloudinative mirrors. |
| `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` was empty because the curl from `raw.githubusercontent.com` returned nothing (kubernetes/release's raw paths reach github CDN — egress-filtered). | Write 10-kubeadm.conf manually with the proper EnvironmentFile + ExecStart referring to `/usr/local/bin/kubelet` (since we installed from binary, not from apt). |
| `kubeadm init --image-repository docker.cloudinative.com/openstackmagnum` fails — wrong prefix for kube-* images. | `--image-repository k8s.cloudinative.com` instead (the registry.k8s.io Nexus proxy). |
| `k8s.cloudinative.com/coredns:v1.11.3` 404s — registry.k8s.io keeps coredns at `coredns/coredns:v1.11.3` (nested namespace). | Use `kubeadm config` file with `dns.imageRepository: k8s.cloudinative.com/coredns` + `dns.imageTag: v1.11.3`. (See `Phase 6` section.) |
| heredoc `\$KUBELET_KUBECONFIG_ARGS` got double-escaped via nested ssh, kubelet saw the literal string. | Write the 10-kubeadm.conf as a local file on dev05, scp through the openstack VM to the k8s VM. (Don't try to embed it in nested heredocs.) |
| `flannel-cni-plugin` image doesn't exist on cloudinative repos. Helm chart for flannel doesn't exist on `helm.cloudinative.com` (legacy archive). | Apply the manifest YAML directly: `curl https://raw.githubusercontent.com/flannel-io/flannel/v0.26.3/Documentation/kube-flannel.yml` via SOCKS5, sed `docker.io/flannel/` → `docker.cloudinative.com/flannel/`, `kubectl apply`. |
| `tcp/6443` ingress not in cloudinative project's default SG. kubectl from operator's network times out. | Add `openstack security group rule create --proto tcp --dst-port 6443 --ingress --remote-ip 0.0.0.0/0 <default-sg-id>`. |

## Phase 7 — Operator-side fixes (no repo change needed, but for the record)

| Issue | Operator fix |
|---|---|
| `docker-quay.cloudinative.com` initially served the Nexus UI SPA on `/v2/` blob requests (DNS A record was missing, fell through to wildcard → repo.cloudinative.com → Nexus UI). | Operator added `docker-quay` A record to bind, wired nginx `server_name docker-quay.cloudinative.com` to `proxy_pass http://127.0.0.1:5004` (quay-proxy port). |
| `cloudinative.com` zone has wildcard `* IN A 46.245.69.209` fallthrough into operator's existing platform — any new subdomain silently resolves to the old cluster. | Operator added explicit `openstack IN A 95.156.253.235` above the wildcard, bumped SOA, `rndc reload`. (See `patches/README.md` item 7 + `docs/cloudinative-mirror.md` — Authority chain.) |

## Index of fixes by file

- All code paths above either land in `patches/README.md` (8 numbered items, runtime config) OR are baked into committed files:
  - `kolla/globals.yml` — enable_valkey, neutron_dns_domain trailing period, docker_apt_package, enable_docker_repo, octavia_network_type
  - `host-config/netplan/61-vips.yaml` — VIPs as ens3 secondaries
  - `host-config/etc-hosts.pin` — escape wildcard fallthrough for openstack.cloudinative.com
  - `systemd-units/` — etcd discovery stub, br-ex up, octavia interface
  - `docker-images/heat-container-agent/` — patched CA-bundle install (FCOS driver only — archived for context)
  - `scripts/post-deploy-bootstrap.sh` — cloudinative project + flavors + SG + keypair (incl. icmp/22/80/443/6443 ingress)
