##############################################################################
# OpenStack Lab - Outputs
#
# Post-apply reference for connecting to VMs and verifying deployment.
##############################################################################

output "network_map" {
  description = "Lab network to production VLAN mapping"
  value = {
    "lab-mgmt (192.168.100.0/24)"    = "→ Production vlan30  (172.40.30.0/24)"
    "lab-api (192.168.204.0/24)"     = "→ Production vlan204 (172.30.204.0/23)"
    "lab-ext (192.168.206.0/24)"     = "→ Production vlan206 (172.30.206.0/23)"
    "lab-octavia (192.168.202.0/24)" = "→ Production vlan202 (172.30.202.0/23)"
    "lab-storage (192.168.210.0/24)" = "→ Production vlan210 (172.30.210.0/23)"
    "lab-tunnel (192.168.212.0/24)"  = "→ Production vlan212 (172.30.212.0/23)"
  }
}

output "kolla_vip_config" {
  description = "Suggested Kolla VIP addresses for the lab"
  value = {
    kolla_internal_vip = "192.168.204.10"
    kolla_external_vip = "192.168.206.10"
  }
}

output "ansible_inventory_hint" {
  description = "Kolla-Ansible inventory group mapping"
  value = {
    control   = ["lab-ctrl01", "lab-ctrl02", "lab-ctrl03"]
    compute   = ["lab-ctrl01", "lab-ctrl02", "lab-ctrl03", "lab-comp04", "lab-comp05"]
    network   = ["lab-ctrl01", "lab-ctrl02", "lab-ctrl03"]
    storage   = ["lab-ctrl01", "lab-ctrl02", "lab-ctrl03", "lab-comp04", "lab-comp05"]
    monitoring = ["lab-ctrl01", "lab-ctrl02", "lab-ctrl03"]
  }
}
