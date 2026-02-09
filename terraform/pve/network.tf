resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0_nuc1" {
  node_name  = "nuc-1"
  name       = "vmbr0"

  address = "192.168.5.21/24"
  gateway = "192.168.5.1"

  ports = [
    "enp89s0"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0_nuc2" {
  node_name  = "nuc-2"
  name       = "vmbr0"

  address = "192.168.5.22/24"
  gateway = "192.168.5.1"

  ports = [
    "enp89s0"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr0_server1" {
  node_name  = "server-1"
  name       = "vmbr0"

  address = "192.168.5.25/24"
  gateway = "192.168.5.1"

  ports = [
    "enp42s0"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_nuc1" {
  node_name  = "nuc-1"
  name       = "vmbr10"
  vlan_aware = true

  address = "10.0.0.10/24"

  ports = [
    "enx6c1ff772390f"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_nuc2" {
  node_name  = "nuc-2"
  name       = "vmbr10"
  vlan_aware = true

  address = "10.0.0.11/24"

  ports = [
    "enx6c1ff772646d"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr10_server1" {
  node_name  = "server-1"
  name       = "vmbr10"
  vlan_aware = true

  address = "10.0.0.12/24"

  ports = [
    "enp7s0"
  ]
}

resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_1_nuc1" {
  node_name = "nuc-1"
  name      = "${proxmox_virtual_environment_network_linux_bridge.vmbr10_nuc1.name}.1"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_1_nuc2" {
  node_name = "nuc-2"
  name      = "${proxmox_virtual_environment_network_linux_bridge.vmbr10_nuc2.name}.1"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_2_nuc2" {
  node_name = "nuc-2"
  name      = "${proxmox_virtual_environment_network_linux_bridge.vmbr10_nuc2.name}.2"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_2_server1" {
  node_name = "server-1"
  name      = "${proxmox_virtual_environment_network_linux_bridge.vmbr10_server1.name}.2"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_3_server1" {
  node_name = "server-1"
  name      = "${proxmox_virtual_environment_network_linux_bridge.vmbr10_server1.name}.3"
}
resource "proxmox_virtual_environment_network_linux_vlan" "vmbr10_3_nuc1" {
  node_name = "nuc-1"
  name      = "${proxmox_virtual_environment_network_linux_bridge.vmbr10_nuc1.name}.3"
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr11_nuc1" {
  node_name  = "nuc-1"
  name       = "vmbr11"
  vlan_aware = true

  address = "10.0.1.10/24"

  ports = [
    "enx9c69d320e0b2"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr11_nuc2" {
  node_name  = "nuc-2"
  name       = "vmbr11"
  vlan_aware = true

  address = "10.0.1.11/24"

  ports = [
    "enxc8a362104ed6"
  ]
}

resource "proxmox_virtual_environment_network_linux_bridge" "vmbr11_server1" {
  node_name  = "server-1"
  name       = "vmbr11"
  vlan_aware = true

  address = "10.0.1.12/24"

  ports = [
    "enp6s0"
  ]
}
