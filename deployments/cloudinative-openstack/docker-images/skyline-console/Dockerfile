# Custom Skyline UI with cloudinative branding.
# Build context: ./ (must contain cloud-logo.svg, logo.png, loginRightLogo.png, favicon.ico from branding/assets/)
# Build:  docker build -t registry.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1 .
# Push:   docker push registry.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1
# Then in globals.yml: skyline_console_image_full: docker.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1
FROM docker-quay.cloudinative.com/openstack.kolla/skyline-console:2026.1-ubuntu-noble
COPY cloud-logo.svg /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/cloud-logo.svg
COPY cloud-logo.svg /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/cloud-logo-white.svg
COPY logo.png /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/logo.png
COPY loginRightLogo.png /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/asset/image/loginRightLogo.png
COPY favicon.ico /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/favicon.ico
RUN sed -i "s|<title>.*</title>|<title>Cloudinative</title>|" /var/lib/kolla/venv/lib/python3.12/site-packages/skyline_console/static/index.html
