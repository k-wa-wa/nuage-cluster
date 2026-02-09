resource "proxmox_virtual_environment_sdn_zone_evpn" "zone_shared" {
  id         = "shared"
  nodes      = ["nuc-1", "nuc-2", "server-1"]
  controller = "bgp-evpn"
  vrf_vxlan  = 4000
  mtu = 1450
  exit_nodes = ["nuc-1", "nuc-2", "server-1"]

  depends_on = [
    proxmox_virtual_environment_sdn_applier.finalizer
  ]
}

resource "proxmox_virtual_environment_sdn_vnet" "core_services" {
  id   = "core"
  zone = proxmox_virtual_environment_sdn_zone_evpn.zone_shared.id
  tag = 1001
}
resource "proxmox_virtual_environment_sdn_subnet" "core_services" {
  vnet = proxmox_virtual_environment_sdn_vnet.core_services.id
  cidr = "10.10.1.0/24"
  snat = true
}

resource "proxmox_virtual_environment_sdn_vnet" "database_services" {
  id   = "database"
  zone = proxmox_virtual_environment_sdn_zone_evpn.zone_shared.id
  tag = 1002
}
resource "proxmox_virtual_environment_sdn_subnet" "database_services" {
  vnet = proxmox_virtual_environment_sdn_vnet.database_services.id
  cidr = "10.10.2.0/24"
  gateway = "10.10.2.1"
  snat = true
}

resource "proxmox_virtual_environment_sdn_vnet" "storage_services" {
  id   = "storage"
  zone = proxmox_virtual_environment_sdn_zone_evpn.zone_shared.id
  tag = 1003
}
resource "proxmox_virtual_environment_sdn_subnet" "storage_services" {
  vnet = proxmox_virtual_environment_sdn_vnet.storage_services.id
  cidr = "10.10.3.0/24"
  snat = true
}

resource "proxmox_virtual_environment_sdn_applier" "example_applier" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_zone_evpn.zone_shared,
      proxmox_virtual_environment_sdn_vnet.core_services,
      proxmox_virtual_environment_sdn_subnet.core_services,
      proxmox_virtual_environment_sdn_vnet.database_services,
      proxmox_virtual_environment_sdn_subnet.database_services,
      proxmox_virtual_environment_sdn_vnet.storage_services,
      proxmox_virtual_environment_sdn_subnet.storage_services,
    ]
  }

  depends_on = [
      proxmox_virtual_environment_sdn_zone_evpn.zone_shared,
      proxmox_virtual_environment_sdn_vnet.core_services,
      proxmox_virtual_environment_sdn_subnet.core_services,
      proxmox_virtual_environment_sdn_vnet.database_services,
      proxmox_virtual_environment_sdn_subnet.database_services,
      proxmox_virtual_environment_sdn_vnet.storage_services,
      proxmox_virtual_environment_sdn_subnet.storage_services,
  ]
}

resource "proxmox_virtual_environment_sdn_applier" "finalizer" {
}