module "k8s-cluster" {
  source = "../../modules/k8s-cluster"
  cluster_config = {
    cluster = {
      name     = "shared"
      gateway  = "10.10.1.1"
      cidr     = 24
      endpoint = "10.10.1.10"
    }
    nodes = {
      "controlplane-01" = {
        type                  = "controlplane"
        vm_id                 = 103
        vm_name               = "controlplane-01"
        node_name             = "nuc-1"
        cores                 = 2
        memory                = 2048
        bridge                = "core"
        management_ip_address = "192.168.5.185"
        ip_address            = "10.10.1.10"
        cidr                  = 24
        disk_size             = 20
      },
      "worker-01" = {
        type                  = "worker"
        vm_id                 = 104
        vm_name               = "worker-01"
        node_name             = "nuc-2"
        cores                 = 2
        memory                = 2048
        bridge                = "core"
        management_ip_address = "192.168.5.186"
        ip_address            = "10.10.1.11"
        cidr                  = 24
        disk_size             = 20
      }
    }
  }
}
