# Skyline / Horizon UI branding for cloudinative

Operator (ars1364) supplied the two source assets on 2026-06-15:
- `https://aries.cloudinative.com/asset/image/cloud-logo.svg` -> cloud-logo.svg (the blue-cloud "Cloudinative" mark)
- `https://aries.cloudinative.com/favicon.ico` -> favicon.ico (32x32 cloud)

These are not committed here - keep them in the operator's existing aries.cloudinative.com source, this README only records the install commands.

## Install on the running deploy (ephemeral - resets on container rebuild)

```bash
# Fetch from source
curl -fsSLo /tmp/cloud-logo.svg https://aries.cloudinative.com/asset/image/cloud-logo.svg
curl -fsSLo /tmp/favicon.ico    https://aries.cloudinative.com/favicon.ico
# PNG variant for Skyline's logo.png slot
rsvg-convert -w 256 /tmp/cloud-logo.svg -o /tmp/logo.png

# Skyline console (port 9999)
sudo docker cp /tmp/cloud-logo.svg skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/cloud-logo.svg
sudo docker cp /tmp/cloud-logo.svg skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/cloud-logo-white.svg
sudo docker cp /tmp/logo.png       skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/logo.png
sudo docker cp /tmp/favicon.ico    skyline_console:/var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/favicon.ico
sudo docker exec skyline_console sed -i 's|<title>Cloud</title>|<title>Cloudinative</title>|' \
  /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/index.html
sudo docker restart skyline_console

# Horizon (port 443 root path)
sudo docker cp /tmp/favicon.ico    horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/favicon.ico
sudo docker cp /tmp/cloud-logo.svg horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo.svg
sudo docker cp /tmp/cloud-logo.svg horizon:/var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo-splash.svg
sudo docker restart horizon
```

## Persist across kolla-ansible reconfigure (proper way - not done yet)

`/etc/kolla/config/skyline/static-overrides/` and `/etc/kolla/config/horizon/static-overrides/` would be the right paths for kolla-ansible to bind-mount into the container, but the 2026.1 chart only mounts `/etc/kolla/skyline/skyline.yaml` and `/etc/kolla/horizon/local_settings`. There is no first-class "static overlay" mount for either container - you'd need to either:
1. Bake a custom kolla image: extend `docker-quay.cloudinative.com/openstack.kolla/skyline-console:2026.1-ubuntu-noble`, COPY the four files into the right paths, push to `registry.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1`, set `skyline_console_image_full: registry.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1` override in globals.yml. Same for Horizon.
2. Or add the four docker cp commands to a post-deploy step that re-runs after every reconfigure (less correct, sticks until container rebuild).

Track this as TODO: bake into custom kolla images and use a Nexus-hosted tag. Currently kolla rebuild would clobber the branding.
