#!/bin/bash
##############################################################################
# create-network.sh - Create a libvirt virtual network
#
# Idempotent: skips if network already exists and is active.
#
# Usage:
#   ./create-network.sh <name> <bridge> <cidr> <gateway> <dhcp_start> <dhcp_end> <mode>
#
# Example:
#   ./create-network.sh lab-mgmt virbr-mgmt 192.168.100.0/24 192.168.100.1 \
#     192.168.100.100 192.168.100.200 nat
##############################################################################

set -euo pipefail

NAME="$1"
BRIDGE="$2"
CIDR="$3"
GATEWAY="$4"
DHCP_START="$5"
DHCP_END="$6"
MODE="$7"

# Extract prefix length from CIDR
PREFIX="${CIDR##*/}"
NETMASK=$(python3 -c "import ipaddress; print(ipaddress.IPv4Network('$CIDR', strict=False).netmask)")

# Skip if already exists and active
if sudo virsh net-info "$NAME" &>/dev/null; then
  echo "[OK] Network '$NAME' already exists, skipping."
  # Ensure it's started and autostarted
  sudo virsh net-start "$NAME" 2>/dev/null || true
  sudo virsh net-autostart "$NAME" 2>/dev/null || true
  exit 0
fi

# Build forward block based on mode
if [ "$MODE" = "nat" ]; then
  FORWARD="<forward mode='nat'/>"
else
  FORWARD=""
fi

# Generate network XML
cat > "/tmp/${NAME}-net.xml" <<EOF
<network>
  <name>${NAME}</name>
  <bridge name='${BRIDGE}' stp='on' delay='0'/>
  ${FORWARD}
  <ip address='${GATEWAY}' netmask='${NETMASK}'>
    <dhcp>
      <range start='${DHCP_START}' end='${DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF

# Define, start, autostart
sudo virsh net-define "/tmp/${NAME}-net.xml"
sudo virsh net-start "$NAME"
sudo virsh net-autostart "$NAME"

rm -f "/tmp/${NAME}-net.xml"
echo "[OK] Network '$NAME' created (${CIDR}, bridge=${BRIDGE}, mode=${MODE})"
