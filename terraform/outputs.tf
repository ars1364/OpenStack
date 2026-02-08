output "vm_id" {
  description = "OpenStack instance ID"
  value       = openstack_compute_instance_v2.vm.id
}

output "vm_ip" {
  description = "VM IP address"
  value       = openstack_compute_instance_v2.vm.access_ip_v4
}

output "vm_name" {
  description = "VM name"
  value       = openstack_compute_instance_v2.vm.name
}

output "boot_volume_id" {
  description = "Boot volume ID"
  value       = openstack_blockstorage_volume_v3.boot.id
}

output "data_volume_id" {
  description = "Data volume ID"
  value       = openstack_blockstorage_volume_v3.data.id
}

output "data_volume_device" {
  description = "Data volume device path"
  value       = openstack_compute_volume_attach_v2.data.device
}
