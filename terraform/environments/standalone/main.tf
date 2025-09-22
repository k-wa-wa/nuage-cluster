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

// TODO: ubuntu-vm モジュールを使用した書き方に変更する（VMを削除できないため保留）
module "pve_vm" {
  source = "../../modules/vm"
  vms_config = {
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
  }
}

module "oc1-bastion" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1162
    vm_name = "oc1-bastion"
    node_name = "server-1"
    cores = 2
    memory = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      },
      {
        bridge = "vmbr2"
      }
    ]
    ip_config = [
      {
          address = "192.168.5.162/24"
          gateway = "192.168.5.1"
        },
        {
          address = "192.168.20.1/24"
        }
    ]
    ci_user = "ubuntu"
    disk_size = 20
  }
}
