# ============================================================================
# Network Configuration for OpenStack Lab VMs
#
# Each VM gets 6 NICs matching the production VLAN layout:
#   ens3  → Management (SSH, Ansible)      192.168.100.x/24
#   ens4  → API / Internal (Kolla VIP)     192.168.204.x/24
#   ens5  → External (Floating IPs)        192.168.206.x/24
#   ens6  → Octavia LB management          192.168.202.x/24
#   ens7  → Storage traffic                192.168.210.x/24
#   ens8  → Tunnel / Overlay               192.168.212.x/24
#
# Only the management NIC has a default gateway (for outbound/SSH).
# All other NICs are isolated inter-VM networks.
# ============================================================================

version: 2
ethernets:
  ens3:
    addresses:
      - ${mgmt_ip}/24
    gateway4: 192.168.100.1
    nameservers:
      addresses:
        - 192.168.100.1
  ens4:
    addresses:
      - ${api_ip}/24
  ens5:
    addresses:
      - ${ext_ip}/24
  ens6:
    addresses:
      - ${oct_ip}/24
  ens7:
    addresses:
      - ${stor_ip}/24
  ens8:
    addresses:
      - ${tun_ip}/24
