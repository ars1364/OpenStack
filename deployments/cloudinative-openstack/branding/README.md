# Skyline / Horizon UI branding for cloudinative

Operator (ars1364) supplied four source assets on 2026-06-15 + 2026-06-17:

- `assets/cloud-logo.svg`  — 16.5 KB, the blue cloud "Cloudinative" mark (source: https://aries.cloudinative.com/asset/image/cloud-logo.svg)
- `assets/logo.png`        — 256×153, 25 KB (source: https://aries.cloudinative.com/asset/image/logo.png)
- `assets/loginRightLogo.png` — 114×55, 3.5 KB (source: https://aries.cloudinative.com/asset/image/loginRightLogo.png)
- `assets/favicon.ico`     — 32×32, 4.3 KB (source: https://aries.cloudinative.com/favicon.ico)

These ARE committed here so a clean rebuild has all the inputs in one place (sources may move).

## Persistence model (the right way)

Two custom kolla images, built from the upstream openstack.kolla images with the brand assets layered in. Tag `cloudinative-1`, pushed to `registry.cloudinative.com/openstack.kolla/`. Configured into kolla via `*_image_full` overrides in globals.yml — survives `kolla-ansible reconfigure` / `deploy` / container restart.

Build:

```bash
docker login registry.cloudinative.com -u admin -p '<Nexus admin pass>'
cd deployments/cloudinative-openstack/docker-images
./build-branded-ui.sh
```

Wire into kolla (already in `../kolla/globals.yml`):

```yaml
skyline_console_image_full: "docker.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1"
horizon_image_full:         "docker.cloudinative.com/openstack.kolla/horizon:cloudinative-1"
```

Apply:

```bash
ssh ubuntu@95.156.253.231 \
  'source ~/venv/bin/activate && \
   ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \
   kolla-ansible reconfigure -i ~/inventory --tags skyline,horizon'
```

## Per-asset placement inside each container

### Skyline console (`docker exec skyline_console ls /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/`)

| Source | Inside container |
|---|---|
| `cloud-logo.svg` | `asset/image/cloud-logo.svg` |
| `cloud-logo.svg` | `asset/image/cloud-logo-white.svg` (same SVG; dark-theme login uses this slot) |
| `logo.png`       | `asset/image/logo.png` |
| `loginRightLogo.png` | `asset/image/loginRightLogo.png` |
| `favicon.ico`    | `favicon.ico` |
| (sed)            | `<title>` rewritten from "Cloud" to "Cloudinative" in `index.html` |

### Horizon (`docker exec horizon ls /var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/`)

| Source | Inside container |
|---|---|
| `favicon.ico`    | `favicon.ico` |
| `cloud-logo.svg` | `logo.svg` |
| `cloud-logo.svg` | `logo-splash.svg` |
| `logo.png`       | `logo.png` |

(Horizon does not have a separate "title" override — it uses the project's `site_branding` setting from `local_settings.py`. The default `OpenStack Dashboard` shows in the browser tab title; rebrand via `SITE_BRANDING = "Cloudinative"` in `/etc/kolla/config/horizon/custom_local_settings` if you want that too. Not done in this commit.)

## One-shot ephemeral install (no rebuild, no reconfigure)

For ad-hoc testing or when you can't push to Nexus:

```bash
cd assets
sudo docker cp cloud-logo.svg     skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/cloud-logo.svg
sudo docker cp cloud-logo.svg     skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/cloud-logo-white.svg
sudo docker cp logo.png           skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/logo.png
sudo docker cp loginRightLogo.png skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/loginRightLogo.png
sudo docker cp favicon.ico        skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/favicon.ico
sudo docker exec skyline_console sed -i 's|<title>.*</title>|<title>Cloudinative</title>|' \
  /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/index.html

sudo docker cp favicon.ico        horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/favicon.ico
sudo docker cp cloud-logo.svg     horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo.svg
sudo docker cp cloud-logo.svg     horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo-splash.svg
sudo docker cp logo.png           horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo.png

sudo docker restart skyline_console horizon
```

These reset on the next container rebuild — only use them as a stop-gap.
