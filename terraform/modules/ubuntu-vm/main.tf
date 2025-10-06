terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "proxmox_vm" {
  vm_id     = var.vm_config.vm_id
  name      = var.vm_config.vm_name
  node_name = var.vm_config.node_name

  cpu {
    cores = var.vm_config.cores
    type = "host"
  }

  memory {
    dedicated = var.vm_config.memory
    floating  = var.vm_config.memory
  }

  initialization {
    dynamic "ip_config" {
      for_each = var.vm_config.ip_config
      content {
        ipv4 {
          address = ip_config.value.address
          gateway = ip_config.value.gateway
        }
      }
    }
    user_account {
      username = var.vm_config.ci_user
      keys     = [trimspace(data.local_file.id_rsa_pub.content)]
    }
  }

  disk {
    datastore_id = "local-zfs"
    file_id      = "local:iso/noble-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = var.vm_config.disk_size
  }

  dynamic "network_device" {
    for_each = var.vm_config.network_devices
    content {
      bridge = network_device.value.bridge
    }
  }

  dynamic "usb" {
    for_each = coalesce(var.vm_config.usb, [])
    content {
      host = usb.value.host
      usb3 = true
    }
  }

  protection = var.vm_config.protection
}

data "local_file" "id_rsa_pub" {
  filename = "../../../.ssh/id_rsa.pub"
}
