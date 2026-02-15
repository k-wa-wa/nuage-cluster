module "k8s-cluster" {
  depends_on = [
    proxmox_virtual_environment_sdn_applier.example_applier,
    proxmox_virtual_environment_sdn_vnet.main_services
  ]

  source = "../modules/k8s-cluster"
  cluster_config = {
    cluster = {
      name        = "private"
      gateway     = "10.20.1.1"
      endpoint    = "10.20.1.110"
      node_subnet = "10.20.1.0/24"
    }
    nodes = {
      "controlplane-01" = {
        type                  = "controlplane"
        vm_id                 = 201
        node_name             = "nuc-1"
        cores                 = 2
        memory                = 2048
        bridge                = proxmox_virtual_environment_sdn_vnet.main_services.id
        management_ip_address = "192.168.5.191"
        ip_address            = "10.20.1.111"
        cidr                  = 24
        disk_size             = 20
      },
      "worker-01" = {
        type                  = "worker"
        vm_id                 = 202
        node_name             = "nuc-2"
        cores                 = 2
        memory                = 2048
        bridge                = proxmox_virtual_environment_sdn_vnet.main_services.id
        management_ip_address = "192.168.5.192"
        ip_address            = "10.20.1.112"
        cidr                  = 24
        disk_size             = 20
      }
    }
  }
}
