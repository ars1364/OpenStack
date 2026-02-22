# Marketplace Image Builder — Lessons Learned

## 1. virt-customize Cannot Resolve DNS

**Problem:** `virt-customize --run-command "apt-get update"` fails with
`Temporary failure resolving 'archive.ubuntu.com'`.

**Root cause:** libguestfs runs commands inside a supermin appliance (minimal VM).
This appliance has no network stack — no DHCP, no DNS, no routing. Even writing
`/etc/resolv.conf` via `--write` or `--run-command` doesn't help because the
appliance's kernel has no network interfaces configured.

**Solution:** Use `qemu-nbd` + `chroot` instead. The chroot inherits the host's
network stack, so DNS and package downloads work normally.

```bash
qemu-nbd --connect=/dev/nbd0 image.qcow2
mount /dev/nbd0p1 /mnt/img
mount --bind /dev /mnt/img/dev
mount -t proc proc /mnt/img/proc
rm -f /mnt/img/etc/resolv.conf
echo "nameserver 8.8.8.8" > /mnt/img/etc/resolv.conf
chroot /mnt/img /bin/bash -c "apt-get update && apt-get install -y ..."
```

## 2. Ubuntu Cloud Images Have a Symlinked resolv.conf

**Problem:** `cp /etc/resolv.conf /mnt/img/etc/resolv.conf` fails with
`not writing through dangling symlink`.

**Root cause:** Ubuntu cloud images ship `/etc/resolv.conf` as a symlink to
`/run/systemd/resolve/stub-resolv.conf`. Inside the chroot, `/run/systemd/resolve/`
doesn't exist, so the symlink is dangling.

**Solution:**
```bash
rm -f /mnt/img/etc/resolv.conf          # Remove the dangling symlink
echo "nameserver 8.8.8.8" > /mnt/img/etc/resolv.conf  # Write real file
# After customization, restore the symlink:
rm -f /mnt/img/etc/resolv.conf
ln -s /run/systemd/resolve/stub-resolv.conf /mnt/img/etc/resolv.conf
```

## 3. Resize BEFORE Installing Packages

**Problem:** Ubuntu 24.04 cloud image has a 2.5GB root partition. Docker CE
installation needs ~400MB. With existing content, the partition fills up and
commands fail with `No space left on device` or `Input/output error`.

**Solution:** Resize the qcow2 image and grow the partition BEFORE chroot:
```bash
qemu-img resize image.qcow2 10G
qemu-nbd --connect=/dev/nbd0 image.qcow2
sgdisk -e /dev/nbd0           # Fix GPT backup header
growpart /dev/nbd0 1          # Grow partition 1
e2fsck -f -y /dev/nbd0p1     # Check filesystem
resize2fs /dev/nbd0p1         # Resize filesystem
mount /dev/nbd0p1 /mnt/img   # Now mount with full space
```

## 4. GPT Backup Header After qemu-img resize

**Problem:** After `qemu-img resize`, `fdisk` warns:
`GPT PMBR size mismatch will be corrected by write`.

**Root cause:** GPT stores a backup header at the end of the disk. When the disk
is resized, the backup header is no longer at the end.

**Solution:** Run `sgdisk -e /dev/nbd0` to relocate the backup header to the
new end of disk, BEFORE running `growpart`.

## 5. Cloud Image Has No Default User

**Problem:** `usermod -aG docker ubuntu` fails with `user 'ubuntu' does not exist`.

**Root cause:** The `ubuntu` user is created by cloud-init on first boot, not
baked into the image.

**Solution:** Use cloud-init configuration to add groups:
```yaml
# /etc/cloud/cloud.cfg.d/99-docker.cfg
system_info:
  default_user:
    groups: [adm, cdrom, dip, lxd, sudo, docker]
```

## 6. machine-id Must Be Truncated

**Problem:** Multiple VMs booted from the same image get the same machine-id,
causing DHCP conflicts and duplicate hostnames.

**Solution:** Always truncate machine-id before finalizing the image:
```bash
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
```
cloud-init regenerates it on first boot.

## 7. Compact Images with qemu-img convert -c

**Problem:** After installing packages and cleaning up, the qcow2 file still
contains allocated-but-freed blocks, making it larger than necessary.

**Solution:**
```bash
qemu-img convert -O qcow2 -c source.qcow2 compacted.qcow2
```
The `-c` flag enables compression. A 10GB virtual disk with ~1.9GB used
compresses to ~900MB.

## 8. Docker daemon.json registry-mirrors

For airgap environments, configure Docker to pull through a local registry mirror:
```json
{
  "registry-mirrors": ["https://docker.cloudinative.com"]
}
```
This means `docker pull nginx` automatically tries the mirror first.
The mirror must be a Docker Registry V2 proxy (Nexus, Harbor, etc.).

## 9. APT Sources Format (DEB822)

Ubuntu 24.04 uses the new DEB822 format (`/etc/apt/sources.list.d/ubuntu.sources`)
instead of the legacy one-line format (`/etc/apt/sources.list`).

```
Types: deb
URIs: https://archive.cloudinative.com/ubuntu
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
```

When switching to custom mirrors, update the `.sources` file AND remove
the legacy `sources.list` if it exists.

## 10. Glance Image Properties for OpenStack

Set hardware properties so instances use virtio (best performance):
```bash
openstack image create \
  --property hw_disk_bus=virtio \
  --property hw_vif_model=virtio \
  --property os_type=linux \
  --property os_distro=ubuntu \
  --property os_version=24.04
```

Use `--min-disk` and `--min-ram` to prevent users from launching with
undersized flavors.

## 11. Transfer Large Files Over Slow/Unreliable Links

For transferring images over WireGuard tunnels or other slow links:
- Use `rsync -avP --partial --timeout=120` with retry loops
- `--partial` preserves incomplete files for resume
- `--timeout` prevents infinite hangs
- `-o ServerAliveInterval=10` keeps SSH alive
- Wrap in a bash retry loop (5-20 attempts)
- Pre-compress with `qemu-img convert -c` to minimize transfer size

## 12. aria2c for Resilient Downloads

`wget` and `curl` often fail on slow/filtered connections. `aria2c` with
multi-connection downloads (`--max-connection-per-server=4 --split=4`)
is far more reliable for downloading large files.

## 13. Containerd CRI Ignores hosts.toml Mirror Configs

**Problem:** `kubeadm config images pull` and `crictl pull` ignore the
`/etc/containerd/certs.d/*/hosts.toml` mirror configurations and still try
to reach the original registries directly (getting 403 from Iran).

**Root cause:** Containerd's CRI plugin (used by kubeadm/crictl) does NOT
properly use the hosts.toml-based mirror config. This is a known limitation.
Only `ctr` with `--hosts-dir` flag correctly resolves the mirrors.

**Solution:** Pre-pull all required K8s images during image build using `ctr`:
```bash
ctr -n k8s.io images pull \
  --hosts-dir /etc/containerd/certs.d \
  --platform linux/amd64 \
  registry.k8s.io/kube-apiserver:v1.32.12
```

For users who need additional images in Iran:
```bash
# Works (uses mirrors):
sudo ctr -n k8s.io images pull --hosts-dir /etc/containerd/certs.d <image>

# Does NOT work from Iran (ignores mirrors):
sudo crictl pull <image>
sudo kubeadm config images pull
```

Pre-pulled images cover `kubeadm init` requirements, so this limitation
only affects pulling extra images post-deployment.

## 14. Use `ctr` with k8s.io Namespace for kubeadm

**Problem:** Images pulled with `ctr` into the default namespace are not
visible to kubeadm/kubelet.

**Root cause:** kubeadm and kubelet use the `k8s.io` containerd namespace.
Images in the default namespace are invisible to them.

**Solution:** Always specify `-n k8s.io` when pulling images for Kubernetes:
```bash
ctr -n k8s.io images pull ...
ctr -n k8s.io images list   # verify
```

## 15. containerd Must Be Running for ctr Image Pulls

**Problem:** `ctr images pull` fails in chroot because containerd is not running.

**Solution:** Start containerd temporarily during the build:
```bash
containerd &
CONTAINERD_PID=$!
sleep 3
# ... pull images ...
kill $CONTAINERD_PID
```

This works in chroot because /dev, /proc, /sys are bind-mounted from the host.

## 16. pkgs.k8s.io is Accessible from Iran

Unlike `registry.k8s.io` (Google sanctions 403), the APT repository at
`pkgs.k8s.io` CNAMEs to `prod-cdn.packages.k8s.io` which is served by a
CDN that does NOT block Iran. So kubeadm/kubelet/kubectl can be installed
directly without a mirror.

However, for full airgap, you may still want to proxy it through Nexus.

## 17. Image Size Grows Significantly with Pre-pulled Images

| Image | Without pre-pull | With pre-pull |
|-------|-----------------|---------------|
| Docker CE | ~900MB | ~900MB |
| Kubernetes | ~920MB | ~3.1GB |

The K8s core images (apiserver, etcd, coredns, etc.) add ~2GB. This is
expected — the tradeoff is instant `kubeadm init` vs. 3x image size.

Consider offering both variants if storage is a concern.

## 18. Cloud-init Overwrites APT Sources on First Boot

**Problem:** APT mirror config baked into the image (`/etc/apt/sources.list.d/ubuntu.sources`)
gets overwritten by cloud-init on first boot, reverting to default Ubuntu mirrors.

**Root cause:** Cloud-init's `apt` module re-generates APT sources based on the datasource
(OpenStack metadata service). It doesn't preserve customizations made in the image.

**Workaround options:**
1. Set mirrors via cloud-init userdata at instance creation time
2. Use `/etc/cloud/cloud.cfg.d/99-apt-mirrors.cfg` with `apt: primary/security` config
3. Accept it — users who need airgap can reconfigure APT after boot

For marketplace images, option 2 is best:
```yaml
# /etc/cloud/cloud.cfg.d/99-apt-mirrors.cfg
apt:
  primary:
    - arches: [default]
      uri: https://archive.cloudinative.com/ubuntu
  security:
    - arches: [default]
      uri: https://security.cloudinative.com/ubuntu
```

## 19. Snapshot-based Pre-pull vs Build-time Pre-pull

Two approaches to bake pre-pulled images:

**A. Build-time (chroot + ctr):** Start containerd in chroot, pull images,
stop containerd, compact. Cleaner but `ctr` multi-arch export can be flaky.

**B. Snapshot-based:** Launch VM from base image, SSH in, pull images,
cloud-init clean, stop VM, `openstack server image create`. Simpler and
the pulls go through the actual containerd config, but produces larger
images (no qcow2 compression, includes VM runtime artifacts).

We use approach B for K8s because it guarantees the containerd storage
driver has the images in the exact format kubelet expects.
