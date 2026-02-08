resource "proxmox_virtual_environment_sdn_fabric_openfabric" "main" {
  id        = "main"
  ip_prefix = "10.0.1.0/24"

  depends_on = [
    proxmox_virtual_environment_sdn_applier.finalizer
  ]
}

resource "proxmox_virtual_environment_sdn_fabric_node_openfabric" "main_nuc1" {
  fabric_id       = proxmox_virtual_environment_sdn_fabric_openfabric.main.id
  node_id         = "nuc-1"
  ip              = "10.0.1.21"
  interface_names = ["vmbr10"]
}

resource "proxmox_virtual_environment_sdn_fabric_node_openfabric" "main_nuc2" {
  fabric_id       = proxmox_virtual_environment_sdn_fabric_openfabric.main.id
  node_id         = "nuc-2"
  ip              = "10.0.1.22"
  interface_names = ["vmbr10"]
}

resource "proxmox_virtual_environment_sdn_fabric_node_openfabric" "main_server1" {
  fabric_id       = proxmox_virtual_environment_sdn_fabric_openfabric.main.id
  node_id         = "server-1"
  ip              = "10.0.1.25"
  interface_names = ["vmbr10"]
}

resource "proxmox_virtual_environment_sdn_applier" "example_applier" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_fabric_openfabric.main,
      proxmox_virtual_environment_sdn_fabric_node_openfabric.main_nuc1,
      proxmox_virtual_environment_sdn_fabric_node_openfabric.main_nuc2,
      proxmox_virtual_environment_sdn_fabric_node_openfabric.main_server1,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_sdn_fabric_openfabric.main,
    proxmox_virtual_environment_sdn_fabric_node_openfabric.main_nuc1,
    proxmox_virtual_environment_sdn_fabric_node_openfabric.main_nuc2,
    proxmox_virtual_environment_sdn_fabric_node_openfabric.main_server1,
  ]
}

resource "proxmox_virtual_environment_sdn_applier" "finalizer" {
}

# controller を GUI で作成する