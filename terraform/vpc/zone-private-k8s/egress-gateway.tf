module "egress-gateway" {
  source = "../modules/nix-lxc"

  github_access_token = data.sops_file.secrets.data["github_access_token"]

  lxc_config = {
    vm_id     = 220
    vm_name   = "egress-gateway"
    node_name = "server-1"
    cores     = 1
    memory    = 1024
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
        address = "10.20.1.30/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.220/24"
      }
    ]
    disk_size = 4
    startup = {
      order      = "2"
      up_delay   = "10"
      down_delay = "15"
    }
  }
}
