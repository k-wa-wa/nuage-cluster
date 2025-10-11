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

module "oc1-nfs" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1151
    vm_name = "oc1-nfs"
    node_name = "server-1"
    cores = 2
    memory = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.151/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user = "ubuntu"
    disk_size = 1024
    protection = true
  }
}
