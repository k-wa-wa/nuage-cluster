# MinIO の移行先 S3 互換ストレージ (SeaweedFS)。master の raft に 3 台が必要なため、
# nuc-1 / server-2 / server-1 に 1 台ずつ配置する。
# VIP は 10.20.1.60 (keepalived, nix/hosts/swfs-cluster/keepalived.nix)
locals {
  swfs_nodes = {
    "swfs-cluster-1" = {
      vm_id     = 261
      node_name = "nuc-1"
      ip        = "10.20.1.61"
    }
    "swfs-cluster-2" = {
      vm_id     = 262
      node_name = "server-2"
      ip        = "10.20.1.62"
    }
    "swfs-cluster-3" = {
      vm_id     = 263
      node_name = "server-1"
      ip        = "10.20.1.63"
    }
  }
}

module "swfs-cluster" {
  source   = "../modules/nix-lxc"
  for_each = local.swfs_nodes

  lxc_config = {
    vm_id     = each.value.vm_id
    vm_name   = each.key
    node_name = each.value.node_name
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
        address = "${each.value.ip}/24"
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

  # volume server のデータ領域。ディレクトリを 1 つに絞り、容量の二重計上を避ける
  mount_points = [
    {
      volume = "local-zfs"
      size   = "200G"
      path   = "/data"
    }
  ]
}
