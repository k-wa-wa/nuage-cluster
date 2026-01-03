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

module "oc1-pg-1" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1156
    vm_name = "oc1-pg-1"
    node_name = "server-1"
    cores = 4
    memory = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.156/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user = "ubuntu"
    disk_size = 512
    protection = false
  }
}
module "oc1-pg-2" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1157
    vm_name = "oc1-pg-2"
    node_name = "nuc-1"
    cores = 2
    memory = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.157/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user = "ubuntu"
    disk_size = 512
    protection = false
  }
}
module "oc1-pg-3" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1158
    vm_name = "oc1-pg-3"
    node_name = "nuc-2"
    cores = 2
    memory = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.158/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user = "ubuntu"
    disk_size = 512
    protection = false
  }
}
