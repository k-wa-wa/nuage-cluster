resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_nuc1" {
  node_name  = "nuc-1"
  name       = "vmbr10"
  vlan_aware = true

  address = "10.0.1.10/24"

  ports = [
    "enx9c69d320e0b2"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_nuc2" {
  node_name  = "nuc-2"
  name       = "vmbr10"
  vlan_aware = true

  address = "10.0.1.11/24"

  ports = [
    "enxc8a362104ed6"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_server1" {
  node_name  = "server-1"
  name       = "vmbr10"
  vlan_aware = true

  address = "10.0.1.12/24"

  ports = [
    "enp6s0"
  ]
}

resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_1_nuc1" {
  node_name = "nuc-1"
  name      = "vmbr10.1"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_1_nuc2" {
  node_name = "nuc-2"
  name      = "vmbr10.1"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_2_nuc2" {
  node_name = "nuc-2"
  name      = "vmbr10.2"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_2_server1" {
  node_name = "server-1"
  name      = "vmbr10.2"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_3_server1" {
  node_name = "server-1"
  name      = "vmbr10.3"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_3_nuc1" {
  node_name = "nuc-1"
  name      = "vmbr10.3"
}

