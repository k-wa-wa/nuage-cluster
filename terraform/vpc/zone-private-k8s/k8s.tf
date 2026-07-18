module "k8s-cluster" {
  source = "../modules/k8s-cluster"
  cluster_config = {
    cluster = {
      name                 = "private"
      gateway              = "10.20.1.1"
      endpoint             = "10.20.1.10"
      node_subnet          = "10.20.1.0/24"
      additional_cert_sans = ["192.168.5.200"]
    }
    nodes = {
      "controlplane-01" = {
        type       = "controlplane"
        vm_id      = 201
        node_name  = "nuc-1"
        cores      = 2
        memory     = 4096
        bridge     = "prvmain"
        ip_address = "10.20.1.11"
        cidr       = 24
        disk_size  = 20
      },
      "controlplane-02" = {
        type       = "controlplane"
        vm_id      = 202
        node_name  = "nuc-2"
        cores      = 2
        memory     = 4096
        bridge     = "prvmain"
        ip_address = "10.20.1.12"
        cidr       = 24
        disk_size  = 20
      },
      "controlplane-03" = {
        type       = "controlplane"
        vm_id      = 203
        node_name  = "server-1"
        cores      = 2
        memory     = 4096
        bridge     = "prvmain"
        ip_address = "10.20.1.13"
        cidr       = 24
        disk_size  = 20
      },
      "worker-01" = {
        type       = "worker"
        vm_id      = 206
        node_name  = "nuc-1"
        cores      = 4
        memory     = 8192
        bridge     = "prvmain"
        ip_address = "10.20.1.16"
        cidr       = 24
        disk_size  = 100
      },
      "worker-02" = {
        type       = "worker"
        vm_id      = 207
        node_name  = "nuc-2"
        cores      = 4
        memory     = 8192
        bridge     = "prvmain"
        ip_address = "10.20.1.17"
        cidr       = 24
        disk_size  = 100
      },
      "worker-03" = {
        type       = "worker"
        vm_id      = 208
        node_name  = "server-1"
        cores      = 8
        memory     = 16384
        bridge     = "prvmain"
        ip_address = "10.20.1.18"
        cidr       = 24
        disk_size  = 100
      },
    }
  }
}
