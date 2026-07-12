data "sops_file" "secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

module "pg-cluster-1" {
  source   = "../modules/nix-lxc"
  sops_key = data.sops_file.secrets.data["lb_sops_key"]
  lxc_config = {
    vm_id     = 241
    vm_name   = "pg-cluster-1"
    node_name = "nuc-1"
    cores     = 2
    memory    = 8192
    network_devices = [
      {
        name   = "eth0"
        bridge = "dummy"
      },
      {
        name   = "eth1"
        bridge = "prvmain"
      },
      {
        name   = "eth2"
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "dhcp"
      },
      {
        address = "10.20.1.41/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.211/24"
      }
    ]
    disk_size = 40
    startup = {
      order      = "1"
      up_delay   = "10"
      down_delay = "60"
    }
  }
}

module "pg-cluster-2" {
  source   = "../modules/nix-lxc"
  sops_key = data.sops_file.secrets.data["lb_sops_key"]
  lxc_config = {
    vm_id     = 242
    vm_name   = "pg-cluster-2"
    node_name = "nuc-2"
    cores     = 2
    memory    = 8192
    network_devices = [
      {
        name   = "eth0"
        bridge = "dummy"
      },
      {
        name   = "eth1"
        bridge = "prvmain"
      },
      {
        name   = "eth2"
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "dhcp"
      },
      {
        address = "10.20.1.42/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.212/24"
      }
    ]
    disk_size = 40
    startup = {
      order      = "1"
      up_delay   = "10"
      down_delay = "60"
    }
  }
}

module "pg-cluster-3" {
  source   = "../modules/nix-lxc"
  sops_key = data.sops_file.secrets.data["lb_sops_key"]
  lxc_config = {
    vm_id     = 243
    vm_name   = "pg-cluster-3"
    node_name = "server-1"
    cores     = 2
    memory    = 8192
    network_devices = [
      {
        name   = "eth0"
        bridge = "dummy"
      },
      {
        name   = "eth1"
        bridge = "prvmain"
      },
      {
        name   = "eth2"
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "dhcp"
      },
      {
        address = "10.20.1.43/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.213/24"
      }
    ]
    disk_size = 40
    startup = {
      order      = "1"
      up_delay   = "10"
      down_delay = "60"
    }
  }
}
