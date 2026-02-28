module "pg-1" {
  # depends_on = [
  #   proxmox_virtual_environment_sdn_applier.example_applier,
  #   proxmox_virtual_environment_sdn_vnet.main_services
  # ]

  source = "../modules/lxc"
  lxc_config = {
    vm_id     = 215
    vm_name   = "pg-1"
    node_name = "nuc-1"
    cores     = 2
    memory    = 8192
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
        address = "10.20.1.25/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.205/24"
      }
    ]
    disk_size = 40
  }
}
module "pg-2" {
  # depends_on = [
  #   proxmox_virtual_environment_sdn_applier.example_applier,
  #   proxmox_virtual_environment_sdn_vnet.main_services
  # ]

  source = "../modules/lxc"
  lxc_config = {
    vm_id     = 216
    vm_name   = "pg-2"
    node_name = "nuc-2"
    cores     = 2
    memory    = 8192
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
        address = "10.20.1.26/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.206/24"
      }
    ]
    disk_size = 40
  }
}
module "pg-3" {
  # depends_on = [
  #   proxmox_virtual_environment_sdn_applier.example_applier,
  #   proxmox_virtual_environment_sdn_vnet.main_services
  # ]

  source = "../modules/lxc"
  lxc_config = {
    vm_id     = 217
    vm_name   = "pg-3"
    node_name = "server-1"
    cores     = 2
    memory    = 8192
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
        address = "10.20.1.27/24"
        gateway = "10.20.1.1"
      },
      {
        address = "192.168.5.207/24"
      }
    ]
    disk_size = 40
  }
}