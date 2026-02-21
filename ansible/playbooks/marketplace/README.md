# OpenStack Marketplace Image Builder

Ansible-based pipeline for building pre-configured Glance images (marketplace images)
that work in airgap/sanctions-restricted environments.

## Architecture

```
Build Host (any Linux with qemu-nbd)
  └── qemu-nbd + chroot
        ├── Mount cloud image partition
        ├── Bind-mount /dev, /proc, /sys
        ├── Inject /etc/resolv.conf
        ├── Run customization script
        ├── Clean up + truncate machine-id
        └── Compact with qemu-img convert -c

Transfer Chain
  Build Host → rsync → Relay Host → rsync → OpenStack Controller → glance image-create
```

## Why NOT virt-customize?

`virt-customize` (libguestfs) runs commands inside a **supermin appliance** — a minimal
kernel/VM that boots the guest image. This appliance has **no network access** and cannot
resolve DNS. Commands like `apt-get update` or `curl` fail with "Temporary failure resolving".

**Working alternative:** `qemu-nbd` + `chroot`
- Connect image via NBD: `qemu-nbd --connect=/dev/nbd0 image.qcow2`
- Mount root partition: `mount /dev/nbd0p1 /mnt/img`
- Bind-mount `/dev`, `/proc`, `/sys`
- Write `/etc/resolv.conf` with real nameservers
- `chroot /mnt/img /bin/bash -c "..."` — full network access

## Airgap Considerations

All images are built with **cloudinative.com** mirrors pre-configured:

| Service | Mirror URL |
|---------|-----------|
| Ubuntu APT | `https://archive.cloudinative.com/ubuntu` |
| Ubuntu Security | `https://security.cloudinative.com/ubuntu` |
| Docker Hub (pull) | `https://docker.cloudinative.com` (registry-mirrors) |
| Docker CE APT | `https://download.docker.com/linux/ubuntu` (not blocked) |

### What's blocked from Iran (as of 2026-02)

- `quay.io` — Google/AWS CDN 403
- `ghcr.io` — GitHub DPI filtering
- `registry.k8s.io` — Google sanctions 403
- `gcr.io`, `*.pkg.dev` — Google sanctions 403
- `production.cloudflare.docker.com` — Cloudflare 403
- `github.com` — intermittent gov DPI

### What's NOT blocked

- `download.docker.com` — ✅ accessible
- `archive.ubuntu.com` — ✅ accessible (but slow, use mirrors)
- Docker Hub — ✅ accessible
- PyPI, NPM, Go, Helm — ✅ accessible

## Image Properties

All marketplace images are uploaded with these Glance properties:

```
hw_disk_bus=virtio
hw_vif_model=virtio
os_type=linux
os_distro=<distro>
os_version=<version>
marketplace_category=<category>
```

## Cloud-init Integration

Images use cloud-init for first-boot customization:
- **Root partition auto-grows** (growpart + resize2fs)
- **machine-id truncated** — each instance gets unique identity
- **Default user groups** configured via `/etc/cloud/cloud.cfg.d/99-*.cfg`
- **resolv.conf** restored to systemd-resolved symlink

## Available Images

| Image | Base | Software | Size |
|-------|------|----------|------|
| Ubuntu 24.04 - Docker CE | noble cloud image | Docker 29.2.1, Compose, Buildx, containerd | ~900MB |
| Ubuntu 24.04 - Kubernetes | noble cloud image | kubeadm/kubelet/kubectl v1.32, containerd, pre-pulled K8s images | ~3.1GB |

### Kubernetes Image Details

- **containerd** with SystemdCgroup enabled
- **Registry mirrors** pre-configured in `/etc/containerd/certs.d/` for all major registries
- **Pre-pulled images**: kube-apiserver, kube-controller-manager, kube-scheduler, kube-proxy, etcd, coredns, pause
- **Sysctl tuned**: bridge-nf-call-iptables, ip_forward, br_netfilter
- **Swap disabled**, kubelet enabled
- Ready for `kubeadm init` without internet access

> **⚠️ Known limitation:** containerd's CRI plugin ignores `hosts.toml` mirror configs.
> `kubeadm config images pull` will NOT use mirrors. Pre-pulled images cover `kubeadm init`,
> but for additional images use: `sudo ctr -n k8s.io images pull --hosts-dir /etc/containerd/certs.d <image>`

## Usage

```bash
# Build a marketplace image
ansible-playbook -i inventory marketplace/build-image.yml \
  -e image_name=docker-ce \
  -e build_host=<build-server>

# Upload to Glance (run separately or as part of pipeline)
ansible-playbook -i inventory marketplace/upload-to-glance.yml \
  -e image_name=docker-ce \
  -e image_file=/path/to/image.qcow2
```

## Lessons Learned

See [LESSONS.md](./LESSONS.md)
