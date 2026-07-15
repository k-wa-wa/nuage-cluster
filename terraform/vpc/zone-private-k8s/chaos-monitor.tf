module "chaos-monitor" {
  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 250
    vm_name   = "chaos-monitor"
    node_name = "nuc-2"
    cores     = 2
    memory    = 2048
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
        address = "10.20.1.250/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.250/24"
      }
    ]
    disk_size = 10
  }
}
