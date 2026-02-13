variable "cluster_config" {
  type = object({
    cluster = object({
      name        = string
      gateway     = string
      cidr        = number
      endpoint    = string
      node_subnet = string
    })

    nodes = map(object({
      type                  = string // "controlplane" or "worker_node"
      vm_id                 = number
      vm_name               = string
      node_name             = string
      cores                 = number
      memory                = number
      bridge                = string
      ip_address            = string
      management_ip_address = string
      cidr                  = number
      disk_size             = number // GB
    }))
  })
}
