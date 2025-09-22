variable "vm_config" {
  type = object({
    vm_id     = number
    vm_name   = string
    node_name = string
    cores     = number
    memory    = number
    network_devices = list(object({
      bridge = string
    }))
    ip_config = list(object({
      address = string // with mask
      gateway = optional(string)
    }))
    ci_user   = string
    disk_size = number // GB
    usb = optional(list(object({
      host = string
    })))
    protection = optional(bool)
  })
}
