#!/bin/bash
# Build + push the cloudinative-branded skyline-console and horizon images.
# Requires: docker login registry.cloudinative.com (Nexus admin)
set -euo pipefail
cd "$(dirname "$0")"

for service in skyline-console horizon; do
  echo "===== build $service ====="
  cp ../branding/assets/* $service/
  docker build -t "registry.cloudinative.com/openstack.kolla/$service:cloudinative-1" $service/
  docker push   "registry.cloudinative.com/openstack.kolla/$service:cloudinative-1"
  # cleanup so the assets don't sit in the build context after
  rm -f $service/cloud-logo.svg $service/logo.png $service/loginRightLogo.png $service/favicon.ico
done

cat <<MSG

Done. Now in /etc/kolla/globals.yml on the openstack VM (already in the repo
copy under deployments/cloudinative-openstack/kolla/globals.yml):

  skyline_console_image_full: "docker.cloudinative.com/openstack.kolla/skyline-console:cloudinative-1"
  horizon_image_full:         "docker.cloudinative.com/openstack.kolla/horizon:cloudinative-1"

then:

  source ~/venv/bin/activate
  ANSIBLE_COLLECTIONS_PATH=/usr/share/ansible/collections \\
    kolla-ansible reconfigure -i ~/inventory --tags skyline,horizon
MSG
