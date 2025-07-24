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

resource "proxmox_virtual_environment_vm" "proxmox_vms" {
  for_each = var.vms_config

  vm_id     = each.value.vm_id
  name      = each.key
  node_name = each.value.node_name

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
  }

  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip_address
        gateway = each.value.gateway
      }
    }

    user_account {
      username = each.value.ci_user
      keys     = [trimspace(data.local_file.id_rsa_pub.content)]
    }
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image[each.value.node_name].id
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  network_device {
    bridge = "vmbr0"
  }
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each = toset(distinct([for vm in values(var.vms_config) : vm.node_name]))

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

data "local_file" "id_rsa_pub" {
  filename = "../.ssh/id_rsa.pub"
}
