resource "proxmox_virtual_environment_sdn_zone_evpn" "zone1" {
  id         = "evpn1"
  controller = "evpnct1"
  vrf_vxlan  = 20000

  mtu        = 1450
  exit_nodes = ["nuc-1", "nuc-2", "server-1"]
}

resource "proxmox_virtual_environment_sdn_vnet" "zone1_vnet1" {
  id   = "vnet1"
  zone = proxmox_virtual_environment_sdn_zone_evpn.zone1.id
  tag  = 20001
}

resource "proxmox_virtual_environment_sdn_subnet" "sub1_conf" {
  vnet    = proxmox_virtual_environment_sdn_vnet.zone1_vnet1.id
  cidr    = "10.1.1.0/24"
  gateway = "10.1.1.1"
  snat    = true
}

resource "proxmox_virtual_environment_sdn_applier" "apply" {
  depends_on = [
    proxmox_virtual_environment_sdn_subnet.sub1_conf
  ]
}

module "cloud_stack" {
  source = "../../modules/cloud-stack"
  bastion_config = {
    vm_id      = 1500
    node_name  = "nuc-1"
    bridge     = "vnet1"
    ip_address = "10.1.1.10/24"
    gateway    = "10.1.1.1"
  }

  cluster_config = {
    cluster = {
      name     = "cloud-w-k8s"
      gateway  = "10.1.1.1"
      cidr     = 24
      endpoint = "10.1.1.11"
    }

    nodes = {
      "1" = {
        type        = "controlplane"
        vm_id       = 2001
        vm_name     = "cp-1"
        node_name   = "nuc-1"
        cores       = 2
        memory      = 2048
        bridge      = "vnet1"
        ip_address  = "10.1.1.11"
        cidr        = 24
        disk_size   = 20
      },
      "2" = {
        type        = "worker"
        vm_id       = 2002
        vm_name     = "worker-1"
        node_name   = "nuc-2"
        cores       = 2
        memory      = 2048
        bridge      = "vnet1"
        ip_address  = "10.1.1.12"
        cidr        = 24
        disk_size   = 20
      }
    }
  }
}
