##############################################################################
# OpenStack Lab - Terraform Main
#
# Provisions KVM virtual machines on the local HPE DL360 Gen9 hypervisor
# using virt-install (via local-exec). Creates a 5-node topology mirroring
# the production OpenStack cluster.
#
# Why virt-install instead of the libvirt provider directly?
#   The dmacvicar/libvirt v0.9+ provider maps 1:1 to libvirt XML, making
#   it very verbose for complex domains. virt-install is the standard tool,
#   well-documented, and produces clean results.
#
# IMPORTANT - Cloud-init NIC naming:
#   Virtio NICs in Ubuntu cloud images get unpredictable interface names.
#   Cloud-init ISOs must be generated AFTER VMs exist so we can read MAC
#   addresses from `virsh domiflist` and use MAC-based `set-name` in netplan.
#   This is the ONLY reliable way to get predictable NIC names (mgmt0, api0, etc).
#
# IMPORTANT - Cloud-init /etc/hosts:
#   Set `manage_etc_hosts: false` in cloud-init to prevent duplicate hostname
#   entries. Kolla prechecks requires each hostname to resolve to exactly ONE
#   IP (the api_interface IP). Cloud-init's manage_etc_hosts adds mgmt IPs
#   which causes "Hostname has to resolve uniquely" failures.
#
# IMPORTANT - All 6 NICs required from the start:
#   Each VM needs NICs for ALL networks: mgmt, api, ext, octavia, storage, tunnel.
#   Kolla maps bridge interfaces (br-ex→ext0, br-oct→oct0) to physical NICs.
#   Missing a NIC (e.g., oct0 for Octavia) causes deploy failure:
#   "physical_network 'physnet-oct' unknown for flat provider network"
#   Plan all networks in Terraform upfront — adding NICs later requires
#   VM shutdown + virsh attach-interface + cloud-init regen.
#
# Prerequisites:
#   - KVM/libvirt installed and running (Phase 1)
#   - Storage pools: fast, vms, storage (Phase 1)
#   - Ubuntu 24.04 cloud image downloaded to /data/fast/images/
#   - scripts/create-vm.sh and scripts/create-networks.sh
#
# Usage:
#   cd terraform/
#   terraform init
#   terraform plan    # Review what will be created
#   terraform apply   # Create networks + VMs
#
# Destroy:
#   terraform destroy   # Tears down all VMs and networks
##############################################################################

terraform {
  required_version = ">= 1.5"
}

data "local_file" "ssh_pub_key" {
  filename = var.ssh_public_key_path
}

# ---------------------------------------------------------------------------
# Networks
#
# Creates libvirt virtual networks matching production VLANs.
# Runs scripts/create-networks.sh which is idempotent (skips existing).
# ---------------------------------------------------------------------------

resource "null_resource" "networks" {
  for_each = var.networks

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/../scripts/create-network.sh \
        "${each.key}" \
        "${each.value.bridge_name}" \
        "${each.value.cidr}" \
        "${each.value.gateway}" \
        "${each.value.dhcp_start}" \
        "${each.value.dhcp_end}" \
        "${each.value.mode}"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sudo virsh net-destroy ${each.key} 2>/dev/null; sudo virsh net-undefine ${each.key} 2>/dev/null; true"
  }

  triggers = {
    name    = each.key
    cidr    = each.value.cidr
    mode    = each.value.mode
  }
}

# ---------------------------------------------------------------------------
# Cloud-Init ISOs
#
# Generates per-VM cloud-init ISOs with:
#   - Hostname, SSH key, timezone
#   - Static IPs on all 6 networks
#   - APT → cloudinative.com (no public internet access)
#   - Docker from cloudinative.com mirror
#   - Kernel tuning for OpenStack
# ---------------------------------------------------------------------------

resource "null_resource" "cloudinit" {
  for_each = var.vms

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/../scripts/create-cloudinit.sh \
        "${each.key}" \
        "${each.value.mgmt_ip}" \
        "${trimspace(data.local_file.ssh_pub_key.content)}" \
        "${each.value.pool}"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sudo rm -f /data/fast/${each.key}-init.iso /data/vms/${each.key}-init.iso 2>/dev/null; true"
  }

  triggers = {
    name    = each.key
    mgmt_ip = each.value.mgmt_ip
  }
}

# ---------------------------------------------------------------------------
# Virtual Machines
#
# Creates VMs using virt-install with:
#   - CPU: host-passthrough (nested KVM for nova-compute)
#   - Memory: sized per role (control=more, compute=less)
#   - 6 NICs: mgmt, api, ext, octavia, storage, tunnel
#   - Root disk: backed by Ubuntu 24.04 cloud image (CoW via qcow2)
#   - Cloud-init ISO attached for first-boot config
# ---------------------------------------------------------------------------

resource "null_resource" "vms" {
  for_each = var.vms

  provisioner "local-exec" {
    command = <<-EOT
      ${path.module}/../scripts/create-vm.sh \
        "${each.key}" \
        "${each.value.vcpus}" \
        "${each.value.memory_gb}" \
        "${each.value.disk_gb}" \
        "${each.value.pool}"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      sudo virsh destroy ${each.key} 2>/dev/null
      sudo virsh undefine ${each.key} --remove-all-storage 2>/dev/null
      true
    EOT
  }

  triggers = {
    name      = each.key
    vcpus     = each.value.vcpus
    memory_gb = each.value.memory_gb
    disk_gb   = each.value.disk_gb
  }

  depends_on = [
    null_resource.networks,
    null_resource.cloudinit
  ]
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "vm_ips" {
  description = "Management IPs for each lab VM"
  value = { for name, vm in var.vms : name => vm.mgmt_ip }
}

output "ssh_commands" {
  description = "SSH commands to connect to each VM"
  value = { for name, vm in var.vms : name => "ssh ubuntu@${vm.mgmt_ip}" }
}

output "resource_summary" {
  description = "Total resources allocated to lab VMs"
  value = {
    total_vcpus     = sum([for vm in var.vms : vm.vcpus])
    total_memory_gb = sum([for vm in var.vms : vm.memory_gb])
    total_disk_gb   = sum([for vm in var.vms : vm.disk_gb])
    host_vcpus      = 72
    host_memory_gb  = 377
  }
}
