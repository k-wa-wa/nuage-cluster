module "minio-cluster-1" {
  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 271
    vm_name   = "minio-cluster-1"
    node_name = "nuc-1"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        name   = "eth0"
        bridge = "dummy"
      },
      {
        name   = "eth1"
        bridge = "prvmain"
      }
    ]
    ip_config = [
      {
        address = "dhcp"
      },
      {
        address = "10.20.1.71/24"
        gateway = "10.20.1.1"
      }
    ]
    disk_size = 20
    startup = {
      order      = "1"
      up_delay   = "10"
      down_delay = "60"
    }
  }

  mount_points = [
    {
      volume = "local-zfs"
      size   = "20G"
      path   = "/data1"
    },
    {
      volume = "local-zfs"
      size   = "20G"
      path   = "/data2"
    }
  ]
}

module "minio-cluster-2" {
  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 272
    vm_name   = "minio-cluster-2"
    node_name = "nuc-2"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        name   = "eth0"
        bridge = "dummy"
      },
      {
        name   = "eth1"
        bridge = "prvmain"
      }
    ]
    ip_config = [
      {
        address = "dhcp"
      },
      {
        address = "10.20.1.72/24"
        gateway = "10.20.1.1"
      }
    ]
    disk_size = 20
    startup = {
      order      = "1"
      up_delay   = "10"
      down_delay = "60"
    }
  }

  mount_points = [
    {
      volume = "local-zfs"
      size   = "20G"
      path   = "/data1"
    },
    {
      volume = "local-zfs"
      size   = "20G"
      path   = "/data2"
    }
  ]
}
