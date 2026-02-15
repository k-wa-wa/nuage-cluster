variable "cluster_config" {
  type = object({
    cluster = object({
      name        = string
      gateway     = string
      endpoint    = string // vip
      node_subnet = string
    })

    nodes = map(object({
      type                  = string // "controlplane" or "worker_node"
      vm_id                 = number
      node_name             = string
      cores                 = number
      memory                = number
      bridge                = string
      ip_address            = string
      cidr                  = number
      management_ip_address = string // 255.255.255.0
      disk_size             = number // GB
    }))
  })
}
