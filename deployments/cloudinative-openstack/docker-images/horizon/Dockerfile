# Custom Horizon UI with cloudinative branding.
# Build context: ./ (must contain cloud-logo.svg, logo.png, favicon.ico from branding/assets/)
# Build:  docker build -t registry.cloudinative.com/openstack.kolla/horizon:cloudinative-1 .
# Push:   docker push registry.cloudinative.com/openstack.kolla/horizon:cloudinative-1
# Then in globals.yml: horizon_image_full: docker.cloudinative.com/openstack.kolla/horizon:cloudinative-1
FROM docker-quay.cloudinative.com/openstack.kolla/horizon:2026.1-ubuntu-noble
COPY favicon.ico /var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/favicon.ico
COPY cloud-logo.svg /var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo.svg
COPY cloud-logo.svg /var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo-splash.svg
COPY logo.png /var/lib/kolla/venv/lib/python3.12/site-packages/openstack_dashboard/static/dashboard/img/logo.png
