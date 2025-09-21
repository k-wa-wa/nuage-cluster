terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
  }
}

provider "proxmox" {
  insecure = true
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
}

module "pve_vm" {
  source = "../../modules/vm"
  vms_config = {
    "oc1-proxy" = {
      vm_id     = 1160
      node_name = "server-1"
      cores     = 2
      memory    = 4096
      ip_config = [
        {
          address = "192.168.5.160/24"
          gateway = "192.168.5.1"
          bridge = "vmbr0"
        },
        {
          address = "192.168.1.70/24"
          gateway = "192.168.1.1"
          bridge = "vmbr1"
        },
      ]
      ci_user   = "ubuntu"
      disk_size = 20
    },
    "oc1-dns" = {
      vm_id     = 1161
      node_name = "server-1"
      cores     = 1
      memory    = 2048
      ip_config = [
        {
          address = "192.168.5.161/24"
          gateway = "192.168.5.1"
          bridge = "vmbr0"
        }
      ]
      ci_user   = "ubuntu"
      disk_size = 20
    },
    "oc1-nfs" = {
      vm_id     = 1151
      node_name = "server-1"
      cores     = 2
      memory    = 16384
      ip_config = [
        {
          address = "192.168.5.151/24"
          gateway = "192.168.5.1"
          bridge = "vmbr0"
        },
      ]
      ci_user   = "ubuntu"
      disk_size = 1024
      protection = true
    },
    "oc1-bastion" = {
      vm_id = 1170
      node_name = "server-1"
      cores = 2
      memory = 4096
      ip_config = [
        {
          address = "192.168.5.170/24"
          gateway = "192.168.5.1"
          bridge = "vmbr0"
        },
        {
          address = "192.168.20.1/24"
          bridge = "vmbr2"
        }
      ],
      ci_user = "ubuntu"
      disk_size = 20
    }
  }
}
