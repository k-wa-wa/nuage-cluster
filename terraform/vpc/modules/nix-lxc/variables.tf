variable "lxc_config" {
  type = object({
    vm_id     = number
    vm_name   = string
    node_name = string
    cores     = number
    memory    = number
    network_devices = list(object({
      name   = string
      bridge = string
    }))
    ip_config = list(object({
      address = string // with mask
      gateway = optional(string)
    }))
    disk_size = number // GB
    usb = optional(list(object({
      host = string
    })))
    protection = optional(bool)
    startup = optional(object({
      order      = string
      up_delay   = string
      down_delay = string
    }), {
      order      = "3"
      up_delay   = "10"
      down_delay = "15"
    })
  })
}

variable "sops_key" {
  type        = string
  description = "The Age private key for sops-nix"
  sensitive   = true
  default     = ""
}

variable "mount_points" {
  type = list(object({
    volume = string
    size   = optional(string)
    path   = string
  }))
  default = []
}

