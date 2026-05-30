resource "proxmox_virtual_environment_sdn_zone_evpn" "zone_waai" {
  id                = "waai"
  nodes             = ["nuc-1", "nuc-2", "server-1"]
  controller        = "bgp-evpn"
  vrf_vxlan         = 4002
  mtu               = 1450
  exit_nodes        = ["nuc-1", "nuc-2", "server-1"]
  advertise_subnets = true

  depends_on = [
    proxmox_virtual_environment_sdn_applier.finalizer
  ]
}

resource "proxmox_virtual_environment_sdn_vnet" "main_services" {
  id   = "waaimain"
  zone = proxmox_virtual_environment_sdn_zone_evpn.zone_waai.id
  tag  = 401
}
resource "proxmox_virtual_environment_sdn_subnet" "main_services" {
  vnet    = proxmox_virtual_environment_sdn_vnet.main_services.id
  cidr    = "10.30.1.0/24"
  gateway = "10.30.1.1"
  snat    = true
}

resource "proxmox_virtual_environment_sdn_applier" "sdn_applier" {
  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_sdn_zone_evpn.zone_waai,
      proxmox_virtual_environment_sdn_vnet.main_services,
      proxmox_virtual_environment_sdn_subnet.main_services,
    ]
  }

  depends_on = [
    proxmox_virtual_environment_sdn_zone_evpn.zone_waai,
    proxmox_virtual_environment_sdn_vnet.main_services,
    proxmox_virtual_environment_sdn_subnet.main_services,
  ]
}

resource "proxmox_virtual_environment_sdn_applier" "finalizer" {
}
