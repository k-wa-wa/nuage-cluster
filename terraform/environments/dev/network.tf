resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0" {
  node_name = "server-1"
  name      = "vmbr0"

  address = "192.168.5.25/24"
  gateway = "192.168.5.1"


  ports = [
    "enp42s0"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr1" {
  node_name = "server-1"
  name      = "vmbr1"

  address = "192.168.1.60/24"

  ports = [
    "eno1"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr999" {
  node_name = "server-1"
  name      = "vmbr999"

  address = "192.168.0.10/24"

  ports = [
    "enp41s0f1"
  ]
}
