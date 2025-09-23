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

module "oc1-proxy" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1160
    vm_name = "oc1-proxy"
    node_name = "server-1"
    cores = 2
    memory = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      },
      {
        bridge = "vmbr1"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.160/24"
        gateway = "192.168.5.1"
      },
      {
        address = "192.168.1.70/24"
        gateway = "192.168.1.1"
      },
    ]
    ci_user = "ubuntu"
    disk_size = 20
  }
}

module "oc1-dns" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1161
    vm_name = "oc1-dns"
    node_name = "server-1"
    cores = 1
    memory = 2048
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.161/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user = "ubuntu"
    disk_size = 20
  }
}
