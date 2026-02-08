# ── Data Sources ──

data "openstack_compute_flavor_v2" "vm" {
  name = var.flavor_name
}

data "openstack_images_image_v2" "ubuntu" {
  name        = var.image_name
  most_recent = true
}

data "openstack_networking_network_v2" "provider" {
  name = var.network_name
}

# ── Boot Volume (SSD) ──

resource "openstack_blockstorage_volume_v3" "boot" {
  name        = "${var.vm_name}-boot"
  description = "Boot volume for ${var.vm_name}"
  size        = var.boot_volume_size
  volume_type = var.boot_volume_type
  image_id    = data.openstack_images_image_v2.ubuntu.id
}

# ── Data Volume (HDD, created separately) ──

resource "openstack_blockstorage_volume_v3" "data" {
  name        = "${var.vm_name}-data"
  description = "Data volume for ${var.vm_name}"
  size        = var.data_volume_size
  volume_type = var.data_volume_type
}

# ── Cloud-Init ──

locals {
  cloud_init = templatefile("${path.module}/templates/cloud-init.yaml", {
    vm_password = var.vm_password
    dns_1       = var.dns_servers[0]
    dns_2       = var.dns_servers[1]
  })
}

# ── Compute Instance ──

resource "openstack_compute_instance_v2" "vm" {
  name        = var.vm_name
  flavor_id   = data.openstack_compute_flavor_v2.vm.id
  user_data   = local.cloud_init
  config_drive = true

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.boot.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  network {
    uuid = data.openstack_networking_network_v2.provider.id
  }

  lifecycle {
    ignore_changes = [user_data]
  }
}

# ── Attach Data Volume ──

resource "openstack_compute_volume_attach_v2" "data" {
  instance_id = openstack_compute_instance_v2.vm.id
  volume_id   = openstack_blockstorage_volume_v3.data.id
}
