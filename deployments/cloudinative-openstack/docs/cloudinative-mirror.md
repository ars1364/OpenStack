# *.cloudinative.com artifact mirror

The OpenStack deploy depends end-to-end on the in-house Nexus Pro at `artifact.cloudinative.com` (172.17.17.118, K1 VPS) plus an nginx reverse-proxy at 176.65.243.214 (`server_name`-based routing) plus the authoritative bind at 46.245.69.222 (`cloudinative.com` zone). This document lists what is at each FQDN — needed for any greenfield rebuild and for the `magnum-capi-helm` migration in `magnum-capi-helm-plan.md`.

## Authority chain

```
ars1364 zone file        nginx reverse proxy           Nexus Pro
db.cloudinative.com  ->  176.65.243.214:443       ->  artifact.cloudinative.com:8081
(46.245.69.222 bind)     (server_name lookup)         (172.17.17.118)
                                                       + per-repo docker ports 5001..5009
```

The bind has a wildcard `* IN A 46.245.69.209` for any subdomain not explicitly listed (fallthrough into the operator's existing platform). For openstack.cloudinative.com -> 95.156.253.235 we added an explicit A record above the wildcard on 2026-06-15 and bumped the SOA.

## Subdomain table

Authoritative as of 2026-06-17. Source: `nginx.conf` server-name blocks on artifact VPS + Nexus repository config (`/service/rest/v1/repositories`).

### Application / package mirrors

| FQDN | Format | Nexus repo | Upstream |
|---|---|---|---|
| `apt.cloudinative.com` | apt | `ubuntu-proxy-mobinhost` | Ubuntu noble/jammy/focal main+universe+multiverse |
| `archive.cloudinative.com` | apt | `ubuntu-proxy` | archive.ubuntu.com |
| `security.cloudinative.com` | apt | `ubuntu-security-proxy` | security.ubuntu.com |
| `yum.cloudinative.com` / `dnf.cloudinative.com` | yum | `alma9-baseos-iranserver` | AlmaLinux 9 BaseOS/AppStream |
| `npm.cloudinative.com` | npm | `npm-group` (proxy of npmjs.org + hmirror + chabokan + ito) | npmjs.org + IR mirrors |
| `pypi.cloudinative.com` | pypi | `pypi-proxy` | pypi.org |
| `go.cloudinative.com` | go | `go-proxy` | proxy.golang.org |
| `maven.cloudinative.com` | maven2 | `maven-public` group | Central + Google + jitpack |
| `gmaven.cloudinative.com` | maven2 | `maven-google` | dl.google.com/dl/android/maven2 |
| `gradle.cloudinative.com` | raw | `gradle-distributions` | services.gradle.org |
| `pub.cloudinative.com` | dart-pub | local dart-pub server :4000 | pub.dev |
| `pub-packages.cloudinative.com` | raw | `pub-packages` | dart-pub package tarballs |
| `android-sdk.cloudinative.com` | raw | `android-sdk` | dl.google.com/android/repository |
| `flutter-sdk.cloudinative.com` | raw | `flutter-sdk` | storage.googleapis.com/flutter_infra_release |
| `helm.cloudinative.com` | helm | `helm-proxy` | charts.helm.sh/stable (legacy archive — **DEPRECATED charts**) |
| `download.cloudinative.com` | raw | `docker-gpg` | docker.com install.sh |

### Container registries (Nexus docker)

| FQDN | nginx -> | Nexus repo | Type | Upstream / contents |
|---|---|---|---|---|
| `docker.cloudinative.com` | :5002 | `docker-group` | group | combines all docker proxies + docker-private |
| `registry.cloudinative.com` | :5003 | `docker-private` | hosted | **writable** — push patched images here |
| `docker-quay.cloudinative.com` | :5004 | `quay-proxy` | proxy | quay.io |
| `ghcr.cloudinative.com` | :5005 | `ghcr-proxy` | proxy | ghcr.io |
| `k8s.cloudinative.com` | :5006 | `k8s-registry` | proxy | registry.k8s.io |
| `gcr.cloudinative.com` | :5007 | `gcr-proxy` | proxy | gcr.io |
| `pkg-dev.cloudinative.com` | :5008 | `pkg-dev-proxy` | proxy | us-docker.pkg.dev |
| `quay.cloudinative.com` | :5003 | `docker-private` | hosted | (same endpoint as `registry.cloudinative.com`, via path-based routing) |
| n/a | :5001 | `docker-hub-proxy` | proxy | registry-1.docker.io (used as docker-group member, not exposed standalone) |
| n/a | :5009 | `docker-hub-ir` | proxy | docker.arvancloud.ir (Iranian docker.io mirror, docker-group member) |

`docker-group` members (the `docker.cloudinative.com` view) = `docker-private`, `docker-hub-proxy`, `docker-hub-ir`, `k8s-registry`, `quay-proxy`, `ghcr-proxy`, `gcr-proxy`. We added `docker-private` to the group on 2026-06-15 so patched images pushed to `registry.cloudinative.com` are also visible through `docker.cloudinative.com`.

### Other

| FQDN | What |
|---|---|
| `artifact.cloudinative.com` | Nexus UI + REST API (`/service/rest/v1/repositories`), admin login `admin / Cl0ud1n@t1ve!Nxs2026` |
| `s3.cloudinative.com` | MinIO S3 endpoint at 172.40.30.25:9000 |
| `files.cloudinative.com` | static file host at 192.168.100.20:80 |
| `openstack.cloudinative.com` | this OpenStack deploy — A record on bind only, not via Nexus (see `patches/README.md` item 7) |

## What the OpenStack deploy consumes

The Kolla-Ansible deploy uses these subdomains directly (in `kolla/globals.yml` plus `/etc/hosts` pins on the VM):

- `docker-quay.cloudinative.com` — `docker_registry` for kolla containers (`docker-quay.cloudinative.com/openstack.kolla/*`)
- `apt.cloudinative.com` — apt sources on the openstack VM (`/etc/apt/sources.list.d/ubuntu.sources`)
- `pypi.cloudinative.com` — pip during `pip install kolla-ansible`, `docker`, `dbus-python` etc on the VM
- `docker.cloudinative.com` — once-installed openstack VM uses this for ad-hoc docker pulls (e.g. Magnum images)
- `registry.cloudinative.com` — `docker push` target for patched magnum images (writable, requires `docker login -u admin`)
- `k8s.cloudinative.com` — kubeadm `--image-repository=k8s.cloudinative.com` (proxies registry.k8s.io)
- `helm.cloudinative.com` — `helm repo add cloudinative https://helm.cloudinative.com` for the (deprecated) legacy stable charts

The Iranian carrier's egress filter blocks docker.io / quay.io / gcr.io / registry.k8s.io / pypi.org / archive.ubuntu.com / dl.k8s.io directly — every dependency flows through the mirror chain.

## Adding a new mirror

To add a new upstream (example: PostgreSQL apt repo):

1. POST a new proxy repo to the Nexus REST API (or via the UI):
   ```bash
   curl -sku admin:"$NEXUS_PASS" -X POST -H 'Content-Type: application/json' \
     -d '{"name":"pgdg-proxy","online":true,"storage":{"blobStoreName":"default","strictContentTypeValidation":true},"apt":{"distribution":"noble-pgdg","flat":false},"proxy":{"remoteUrl":"https://apt.postgresql.org/pub/repos/apt"}}' \
     https://artifact.cloudinative.com/service/rest/v1/repositories/apt/proxy
   ```

2. Add an nginx server block on the artifact VPS (172.17.17.118):
   ```
   server {
     listen 443 ssl http2;
     server_name pgdg.cloudinative.com;
     ssl_certificate /etc/nginx/ssl/certificate.crt;
     ssl_certificate_key /etc/nginx/ssl/private.key;
     location / {
       proxy_pass http://127.0.0.1:8081/repository/pgdg-proxy/;
       proxy_set_header Host pgdg.cloudinative.com;
     }
   }
   ```
   `sudo nginx -t && sudo systemctl reload nginx`.

3. Add the DNS A record (or let the wildcard route work if you don't need a specific host). For an internal-only path the wildcard is enough; for a public subdomain add an explicit A record on the bind at 46.245.69.222 (db.cloudinative.com), bump the SOA, `rndc reload cloudinative.com`.

4. Confirm: `curl -I https://pgdg.cloudinative.com/dists/noble-pgdg/InRelease`.

## Adding a new Helm chart repo

The current `helm.cloudinative.com` proxies the **legacy `charts.helm.sh/stable`** (kubernetes/charts archive), which is read-only and ships only deprecated tags. For modern charts (cert-manager, ingress-nginx, kube-prometheus-stack, capi-helm-charts, etc) you need an additional Nexus helm proxy repo per upstream and either a separate FQDN (e.g. `helm-cert-manager.cloudinative.com`) or a path-based nginx rewrite.

This is a **known gap** — the `magnum-capi-helm` migration plan (`docs/magnum-capi-helm-plan.md` step 2) requires mirroring `https://azimuth-cloud.github.io/capi-helm-charts` and the chart-addon subchart sources. Until that's done, `helm.cloudinative.com` is only useful for archive-era charts.

## Authentication

- **Pull from any proxy repo**: anonymous, no creds needed (the docker-group, k8s-registry, etc all serve without auth)
- **Push to `registry.cloudinative.com` / `docker-private`**: `docker login registry.cloudinative.com -u admin -p '<Nexus admin pass>'`
- **Nexus REST API**: basic auth, `admin / <Nexus admin pass>`

Nexus admin password is operator-controlled, NOT stored in this repo. Standing-instruction location for the secret: ARS local secrets file, NOT shared in git.

## Operator hosts behind cloudinative.com

| Host | IP | Role |
|---|---|---|
| artifact (Nexus VPS) | 172.17.17.118 (WG only) | Nexus Pro 3.91, `admin / <set by operator>` |
| reverse-proxy | 176.65.243.214 | nginx termination for all subdomains, has the *.cloudinative.com wildcard cert |
| dns-server | 46.245.69.222 | bind 9, master for cloudinative.com / imaginelive.com / tichikid.com / devopsplusservice.com zones |
