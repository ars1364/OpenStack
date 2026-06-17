#!/bin/sh
mkdir -p /etc/pki/tls/certs
cp /opt/ca-bundle-cloudinative.crt /etc/pki/tls/certs/ca-bundle.crt
echo "[cloudinative] installed ca-bundle.crt"
exec /usr/bin/start-heat-container-agent
