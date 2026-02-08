resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_nuc1" {
  node_name  = "nuc-1"
  name       = "vmbr10"
  vlan_aware = true

  ports = [
    "enx9c69d320e0b2"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_nuc2" {
  node_name  = "nuc-2"
  name       = "vmbr10"
  vlan_aware = true

  ports = [
    "enxc8a362104ed6"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_server1" {
  node_name  = "server-1"
  name       = "vmbr10"
  vlan_aware = true

  ports = [
    "enp6s0"
  ]
}
