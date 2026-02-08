variable "auth_url" {
  description = "OpenStack Keystone auth URL"
  type        = string
  default     = "https://aries.cloudinative.com:5000/v3"
}

variable "username" {
  description = "OpenStack admin username"
  type        = string
  default     = "admin"
}

variable "password" {
  description = "OpenStack admin password"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Target OpenStack project"
  type        = string
  default     = "VPC_dariaideh"
}

variable "domain_id" {
  description = "OpenStack domain"
  type        = string
  default     = "default"
}

variable "region" {
  description = "OpenStack region"
  type        = string
  default     = "dc1"
}

# ── VM Configuration ──

variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "keemiyamahour-runner"
}

variable "flavor_name" {
  description = "Compute flavor"
  type        = string
  default     = "C4R8"
}

variable "image_name" {
  description = "Boot image name"
  type        = string
  default     = "Ubuntu24"
}

variable "network_name" {
  description = "Network to attach the VM to"
  type        = string
  default     = "Provider"
}

variable "boot_volume_size" {
  description = "Boot volume size in GB"
  type        = number
  default     = 20
}

variable "boot_volume_type" {
  description = "Boot volume type (bus=SSD, eco=HDD)"
  type        = string
  default     = "bus"
}

variable "data_volume_size" {
  description = "Data volume size in GB"
  type        = number
  default     = 2000
}

variable "data_volume_type" {
  description = "Data volume type (bus=SSD, eco=HDD)"
  type        = string
  default     = "eco"
}

variable "vm_password" {
  description = "Password for the ubuntu user (cloud-init)"
  type        = string
  sensitive   = true
}

variable "dns_servers" {
  description = "DNS servers for the VM"
  type        = list(string)
  default     = ["4.2.2.4", "8.8.8.8"]
}
