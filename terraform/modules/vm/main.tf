terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
  }
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
    dynamic "ip_config" {
      for_each = each.value.ip_config
      content {
        ipv4 {
          address = ip_config.value.address
          gateway = ip_config.value.gateway
        }
      }
    }
    user_account {
      username = each.value.ci_user
      keys     = [trimspace(data.local_file.id_rsa_pub.content)]
    }
  }

  disk {
    datastore_id = "ceph-pool-1"
    file_id      = "cephfs-1:iso/noble-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  dynamic "network_device" {
    for_each = zipmap(
      range(
        length(distinct([
          for config in each.value.ip_config : config.gateway
        ]))
      ),
      distinct([
        for config in each.value.ip_config : config.gateway
      ])
    )
    content {
      bridge = "vmbr${network_device.key}"
    }
  }

  dynamic "usb" {
    for_each = each.value.usb_host != null ? [true] : []
    content {
      usb3 = true
      host = each.value.usb_host
    }
  }

  protection = each.value.protection
}

data "local_file" "id_rsa_pub" {
  filename = "../../../.ssh/id_rsa.pub"
}
