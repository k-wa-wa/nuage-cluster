variable "proxmox_endpoint" {
  type    = string
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
    usb_host   = optional(string)
  }))
}
