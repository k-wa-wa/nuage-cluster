module "nfs-proxy" {
  source = "../modules/nix-lxc"

  lxc_config = {
    vm_id     = 220
    vm_name   = "nfs-proxy"
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
  }
}
