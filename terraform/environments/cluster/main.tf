terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
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
    "load-balancer-01" = {
      vm_id      = 1051
      node_name  = "server-1"
      cores      = 2
      memory     = 4096
      ip_config = [
        {
          address = "192.168.5.51/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 20
    },
    "load-balancer-02" = {
      vm_id      = 1052
      node_name  = "nuc-1"
      cores      = 2
      memory     = 4096
      ip_config = [
        {
          address = "192.168.5.52/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 20
    },
    "control-plane-01" = {
      vm_id      = 1061
      node_name  = "nuc-1"
      cores      = 2
      memory     = 4096
      ip_config = [
        {
          address = "192.168.5.61/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 30
    },
    "control-plane-02" = {
      vm_id      = 1062
      node_name  = "nuc-2"
      cores      = 2
      memory     = 4096
      ip_config = [
        {
          address = "192.168.5.62/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 30
    },
    "worker-node-01" = {
      vm_id      = 1071
      node_name  = "nuc-1"
      cores      = 4
      memory     = 16384
      ip_config = [
        {
          address = "192.168.5.71/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 30
    },
    "worker-node-02" = {
      vm_id      = 1072
      node_name  = "server-1"
      cores      = 4
      memory     = 16384
      ip_config = [
        {
          address = "192.168.5.72/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 30
    },
    "worker-node-device-host-01" = {
      vm_id      = 1073
      node_name  = "nuc-2"
      cores      = 6
      memory     = 25476
      ip_config = [
        {
          address = "192.168.5.83/24"
          gateway    = "192.168.5.1"
        }
      ]
      ci_user    = "ubuntu"
      disk_size  = 30
      usb_host   = "13fd:0840"
    },
  }
}
