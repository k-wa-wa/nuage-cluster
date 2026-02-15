resource "proxmox_virtual_environment_sdn_zone_evpn" "zone_private" {
  id                = "private"
  nodes             = ["nuc-1", "nuc-2", "server-1"]
  controller        = "bgp-evpn"
  vrf_vxlan         = 4001
  mtu               = 1450
  exit_nodes        = ["nuc-1", "nuc-2", "server-1"]
  advertise_subnets = true

  depends_on = [
    proxmox_virtual_environment_sdn_applier.finalizer
  ]
}

resource "proxmox_virtual_environment_sdn_vnet" "main_services" {
  id   = "prvmain"
  zone = proxmox_virtual_environment_sdn_zone_evpn.zone_private.id
  tag  = 201
}
resource "proxmox_virtual_environment_sdn_subnet" "main_services" {
  vnet    = proxmox_virtual_environment_sdn_vnet.main_services.id
  cidr    = "10.20.1.0/24"
  gateway = "10.20.1.1"
  snat    = true
}

resource "proxmox_virtual_environment_sdn_applier" "example_applier" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_zone_evpn.zone_private,
      proxmox_virtual_environment_sdn_vnet.main_services,
      proxmox_virtual_environment_sdn_subnet.main_services,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_sdn_zone_evpn.zone_private,
    proxmox_virtual_environment_sdn_vnet.main_services,
    proxmox_virtual_environment_sdn_subnet.main_services,
  ]
}

resource "proxmox_virtual_environment_sdn_applier" "finalizer" {
}
