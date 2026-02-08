resource "proxmox_virtual_environment_sdn_fabric_ospf" "main" {
  id        = "main"
  ip_prefix = "10.254.1.0/24"
  area = 1

  depends_on = [
    proxmox_virtual_environment_sdn_applier.finalizer
  ]
}

resource "proxmox_virtual_environment_sdn_fabric_node_ospf" "main_nuc1" {
  fabric_id       = proxmox_virtual_environment_sdn_fabric_ospf.main.id
  node_id         = "nuc-1"
  ip              = "10.254.1.21"
  interface_names = ["vmbr10.1", "vmbr10.3"]
  
}

resource "proxmox_virtual_environment_sdn_fabric_node_ospf" "main_nuc2" {
  fabric_id       = proxmox_virtual_environment_sdn_fabric_ospf.main.id
  node_id         = "nuc-2"
  ip              = "10.254.1.22"
  interface_names = ["vmbr10.1", "vmbr10.2"]
}

resource "proxmox_virtual_environment_sdn_fabric_node_ospf" "main_server1" {
  fabric_id       = proxmox_virtual_environment_sdn_fabric_ospf.main.id
  node_id         = "server-1"
  ip              = "10.254.1.25"
  interface_names = ["vmbr10.2", "vmbr10.3"]
}

resource "proxmox_virtual_environment_sdn_applier" "example_applier" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_fabric_ospf.main,
      proxmox_virtual_environment_sdn_fabric_node_ospf.main_nuc1,
      proxmox_virtual_environment_sdn_fabric_node_ospf.main_nuc2,
      proxmox_virtual_environment_sdn_fabric_node_ospf.main_server1,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_sdn_fabric_ospf.main,
    proxmox_virtual_environment_sdn_fabric_node_ospf.main_nuc1,
    proxmox_virtual_environment_sdn_fabric_node_ospf.main_nuc2,
    proxmox_virtual_environment_sdn_fabric_node_ospf.main_server1,
  ]
}

resource "proxmox_virtual_environment_sdn_applier" "finalizer" {
}

# controller を GUI で作成する