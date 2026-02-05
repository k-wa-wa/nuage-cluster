variable "cluster_config" {
  type = object({
    cluster = object({
      name     = string
      gateway  = string
      cidr     = number
      endpoint = string
    })

    nodes = map(object({
      type       = string // "controlplane" or "worker_node"
      vm_id      = number
      vm_name    = string
      node_name  = string
      cores      = number
      memory     = number
      bridge     = string
      ip_address = string
      cidr       = number
      disk_size  = number // GB
    }))
  })
}

variable "bastion_config" {
  type = object({
    vm_id                              = number
    node_name                          = string
    bridge                             = string
    ip_address                         = string
    gateway                            = string
    enable_access_from_private_network = bool
  })
}
