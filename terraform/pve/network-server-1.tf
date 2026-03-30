resource "proxmox_virtual_environment_network_linux_bridge" "vmbr1_server_1" {
  node_name = "server-1"
  name      = "vmbr1"

  address = "192.168.1.60/24"

  ports = [
    "eno1"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr999_server_1" {
  node_name = "server-1"
  name      = "vmbr999"

  address = "192.168.0.10/24"

  ports = [
    "enp41s0f1"
  ]
}
