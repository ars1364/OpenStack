##############################################################################
# OpenStack Lab - VM Variables
#
# Defines the virtual machine topology that mirrors the production cluster.
#
# Production layout:
#   server01-03: control + compute + network + storage + monitoring (68 containers each)
#   server04-05: compute + storage only (15 containers each)
#
# Lab scaling:
#   We allocate proportionally within the 72-core / 377GB host budget.
#   Control nodes get more RAM (for MariaDB, RabbitMQ, services).
#   Compute nodes are lighter (just nova-compute, OVN, cinder-volume).
#
# Total allocation: 60 vCPUs / 320 GB RAM (leaves headroom for host + libvirt)
##############################################################################

variable "libvirt_uri" {
  description = "Libvirt connection URI"
  type        = string
  default     = "qemu:///system"
}

variable "base_image_url" {
  description = "Ubuntu 24.04 (Noble) cloud image URL - use local path after download"
  type        = string
  default     = "/data/fast/images/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key for VM access"
  type        = string
  default     = "/home/ubuntu/.ssh/id_ed25519.pub"
}

variable "network_domain" {
  description = "DNS domain for the lab VMs"
  type        = string
  default     = "lab.local"
}

# --------------------------------------------------------------------------
# VM Definitions
#
# Each VM maps to a production server. Roles match the Kolla inventory:
#   control = control + network + monitoring
#   compute = compute + storage
# --------------------------------------------------------------------------

variable "vms" {
  description = "VM topology mirroring production cluster"
  type = map(object({
    vcpus       = number
    memory_gb   = number
    disk_gb     = number
    pool        = string      # libvirt storage pool
    roles       = list(string)
    mgmt_ip     = string      # management network (equivalent to vlan204)
    description = string
  }))

  default = {
    "lab-ctrl01" = {
      vcpus       = 14
      memory_gb   = 80
      disk_gb     = 100
      pool        = "fast"
      roles       = ["control", "network", "compute", "monitoring", "storage", "deployment"]
      mgmt_ip     = "192.168.100.11"
      description = "Control+compute node 1 (mirrors server01 - deployment host)"
    }
    "lab-ctrl02" = {
      vcpus       = 12
      memory_gb   = 64
      disk_gb     = 80
      pool        = "fast"
      roles       = ["control", "network", "compute", "monitoring", "storage"]
      mgmt_ip     = "192.168.100.12"
      description = "Control+compute node 2 (mirrors server02)"
    }
    "lab-ctrl03" = {
      vcpus       = 12
      memory_gb   = 64
      disk_gb     = 80
      pool        = "fast"
      roles       = ["control", "network", "compute", "monitoring", "storage"]
      mgmt_ip     = "192.168.100.13"
      description = "Control+compute node 3 (mirrors server03)"
    }
    "lab-comp04" = {
      vcpus       = 10
      memory_gb   = 48
      disk_gb     = 60
      pool        = "vms"
      roles       = ["compute", "storage"]
      mgmt_ip     = "192.168.100.14"
      description = "Compute+storage node 4 (mirrors server04)"
    }
    "lab-comp05" = {
      vcpus       = 10
      memory_gb   = 48
      disk_gb     = 60
      pool        = "vms"
      roles       = ["compute", "storage"]
      mgmt_ip     = "192.168.100.15"
      description = "Compute+storage node 5 (mirrors server05)"
    }
  }
}

# --------------------------------------------------------------------------
# Network Definitions
#
# Mirrors production VLANs as libvirt isolated/NAT networks.
# Production uses tagged VLANs on physical bonds; lab uses virtual bridges.
#
# VLAN mapping:
#   vlan30  (172.40.30.0/24)    -> lab-mgmt    (192.168.100.0/24)  Management/SSH
#   vlan204 (172.30.204.0/23)   -> lab-api     (192.168.204.0/24)  API/Internal
#   vlan206 (172.30.206.0/23)   -> lab-ext     (192.168.206.0/24)  External/floating IPs
#   vlan202 (172.30.202.0/23)   -> lab-octavia (192.168.202.0/24)  Octavia LB mgmt
#   vlan210 (172.30.210.0/23)   -> lab-storage (192.168.210.0/24)  Storage traffic
#   vlan212 (172.30.212.0/23)   -> lab-tunnel  (192.168.212.0/24)  Tunnel/overlay
# --------------------------------------------------------------------------

variable "networks" {
  description = "Lab networks mirroring production VLANs"
  type = map(object({
    cidr        = string
    gateway     = string
    dhcp_start  = string
    dhcp_end    = string
    mode        = string  # nat, isolated, bridge
    bridge_name = string
    description = string
  }))

  default = {
    "lab-mgmt" = {
      cidr        = "192.168.100.0/24"
      gateway     = "192.168.100.1"
      dhcp_start  = "192.168.100.100"
      dhcp_end    = "192.168.100.200"
      mode        = "nat"
      bridge_name = "virbr-mgmt"
      description = "Management/SSH (mirrors vlan30)"
    }
    "lab-api" = {
      cidr        = "192.168.204.0/24"
      gateway     = "192.168.204.1"
      dhcp_start  = "192.168.204.100"
      dhcp_end    = "192.168.204.200"
      mode        = "nat"
      bridge_name = "virbr-api"
      description = "API/Internal (mirrors vlan204 - kolla_internal_vip)"
    }
    "lab-ext" = {
      cidr        = "192.168.206.0/24"
      gateway     = "192.168.206.1"
      dhcp_start  = "192.168.206.100"
      dhcp_end    = "192.168.206.200"
      mode        = "nat"
      bridge_name = "virbr-ext"
      description = "External/Floating IPs (mirrors vlan206 - kolla_external_vip)"
    }
    "lab-octavia" = {
      cidr        = "192.168.202.0/24"
      gateway     = "192.168.202.1"
      dhcp_start  = "192.168.202.100"
      dhcp_end    = "192.168.202.200"
      mode        = "isolated"
      bridge_name = "virbr-oct"
      description = "Octavia LB management (mirrors vlan202)"
    }
    "lab-storage" = {
      cidr        = "192.168.210.0/24"
      gateway     = "192.168.210.1"
      dhcp_start  = "192.168.210.100"
      dhcp_end    = "192.168.210.200"
      mode        = "isolated"
      bridge_name = "virbr-stor"
      description = "Storage traffic (mirrors vlan210)"
    }
    "lab-tunnel" = {
      cidr        = "192.168.212.0/24"
      gateway     = "192.168.212.1"
      dhcp_start  = "192.168.212.100"
      dhcp_end    = "192.168.212.200"
      mode        = "isolated"
      bridge_name = "virbr-tun"
      description = "Tunnel/overlay network (mirrors vlan212)"
    }
  }
}
