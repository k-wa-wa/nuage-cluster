module "k8s-cluster-new" {
  source = "../modules/k8s-cluster-new"
  cluster_config = {
    cluster = {
      name        = "private-new"
      gateway     = "10.20.1.21"
      endpoint    = "10.20.1.30" # 検証用VIP
      node_subnet = "10.20.1.0/24"
    }
    nodes = {
      # 既存のVMやIPアドレスと衝突しないように300番台・30番台にオフセット
      "controlplane-01" = {
        type                  = "controlplane"
        vm_id                 = 301
        node_name             = "nuc-1"
        cores                 = 2
        memory                = 2048
        bridge                = "prvmain" # 既存のVNetを再利用
        ip_address            = "10.20.1.31"
        cidr                  = 24
        disk_size             = 20
      },
      "controlplane-02" = {
        type                  = "controlplane"
        vm_id                 = 302
        node_name             = "nuc-2"
        cores                 = 2
        memory                = 2048
        bridge                = "prvmain"
        ip_address            = "10.20.1.32"
        cidr                  = 24
        disk_size             = 20
      },
      "controlplane-03" = {
        type                  = "controlplane"
        vm_id                 = 303
        node_name             = "server-1"
        cores                 = 2
        memory                = 2048
        bridge                = "prvmain"
        ip_address            = "10.20.1.33"
        cidr                  = 24
        disk_size             = 20
      },
      "worker-01" = {
        type                  = "worker"
        vm_id                 = 306
        node_name             = "nuc-1"
        cores                 = 4
        memory                = 8192
        bridge                = "prvmain"
        ip_address            = "10.20.1.36"
        cidr                  = 24
        disk_size             = 20
      },
      "worker-02" = {
        type                  = "worker"
        vm_id                 = 307
        node_name             = "nuc-2"
        cores                 = 4
        memory                = 8192
        bridge                = "prvmain"
        ip_address            = "10.20.1.37"
        cidr                  = 24
        disk_size             = 20
      },
      "worker-03" = {
        type                  = "worker"
        vm_id                 = 308
        node_name             = "server-1"
        cores                 = 8
        memory                = 16384
        bridge                = "prvmain"
        ip_address            = "10.20.1.38"
        cidr                  = 24
        disk_size             = 20
      },
    }
  }
}
