module "lb-1" {
  # depends_on = [
  #   proxmox_virtual_environment_sdn_applier.example_applier,
  #   proxmox_virtual_environment_sdn_vnet.main_services
  # ]

  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 211
    vm_name   = "lb-1"
    node_name = "nuc-1"
    cores     = 1
    memory    = 2048
    network_devices = [
      {
        name   = "eth0"
        bridge = "prvmain"
      },
      {
        name = "eth1"
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "10.20.1.21/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.201/24"
      }
    ]
    disk_size = 4
  }
}

module "lb-2" {
  # depends_on = [
  #   proxmox_virtual_environment_sdn_applier.example_applier,
  #   proxmox_virtual_environment_sdn_vnet.main_services
  # ]

  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 212
    vm_name   = "lb-2"
    node_name = "nuc-2"
    cores     = 1
    memory    = 2048
    network_devices = [
      {
        name   = "eth0"
        bridge = "prvmain"
      },
      {
        name = "eth1"
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "10.20.1.22/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.202/24"
      }
    ]
    disk_size = 4
  }
}

module "lb-3" {
  # depends_on = [
  #   proxmox_virtual_environment_sdn_applier.example_applier,
  #   proxmox_virtual_environment_sdn_vnet.main_services
  # ]

  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 213
    vm_name   = "lb-3"
    node_name = "server-1"
    cores     = 1
    memory    = 2048
    network_devices = [
      {
        name   = "eth0"
        bridge = "prvmain"
      },
      {
        name = "eth1"
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "10.20.1.23/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.203/24"
      }
    ]
    disk_size = 4
  }
}
