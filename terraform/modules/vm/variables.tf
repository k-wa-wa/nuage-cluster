variable "vms_config" {
  type = map(object({
    vm_id     = number
    node_name = string
    cores     = number
    memory    = number
    machine   = optional(string)
    ip_config = list(object({
      address = string // with mask
      gateway = string
    }))
    ci_user   = string
    disk_size = number // GB
    usb_host  = optional(string)
    hostpci = optional(list(object({
      device = string
      id     = string
      pcie   = bool
    })))
  }))
}
