resource "proxmox_virtual_environment_network_linux_bridge" "dummy_nuc1" {
  node_name = "nuc-1"
  name      = "dummy"

  address = "192.168.99.21/24"
}

resource "proxmox_virtual_environment_network_linux_bridge" "dummy_nuc2" {
  node_name = "nuc-2"
  name      = "dummy"

  address = "192.168.99.22/24"
}

resource "proxmox_virtual_environment_network_linux_bridge" "dummy_server1" {
  node_name = "server-1"
  name      = "dummy"

  address = "192.168.99.25/24"
}