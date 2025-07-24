variable "proxmox_endpoint" {
  type = string
  default = "https://192.168.5.21:8006/api2/json"
}
variable "proxmox_username" {
  type      = string
  sensitive = true
}
variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "vms_config" {
  type = map(object({
    vm_id      = number
    node_name  = string
    cores      = number
    memory     = number
    ip_address = string // with mask
    gateway    = string
    ci_user    = string
    disk_size  = number // GB
  }))
  default = {
    "control-plane-01" = {
      vm_id      = 1001
      node_name  = "nuc1"
      cores      = 2
      memory     = 4096
      ip_address = "192.168.5.61/24"
      gateway    = "192.168.5.1"
      ci_user    = "ubuntu"
      disk_size  = 30
    },
    "control-plane-02" = {
      vm_id      = 1002
      node_name  = "nuc2"
      cores      = 2
      memory     = 4096
      ip_address = "192.168.5.62/24"
      gateway    = "192.168.5.1"
      ci_user    = "ubuntu"
      disk_size  = 30
    }
  }
}
