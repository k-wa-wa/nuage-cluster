resource "proxmox_virtual_environment_container" "lxc" {
  node_name = var.lxc_config.node_name
  vm_id     = var.lxc_config.vm_id

  unprivileged = false
  features {
    nesting = true
  }

  cpu {
    cores = var.lxc_config.cores
  }
  memory {
    dedicated = var.lxc_config.memory
  }

  dynamic "network_interface" {
    for_each = var.lxc_config.network_devices
    content {
      name   = network_interface.value.name
      bridge = network_interface.value.bridge
    }
  }

  initialization {
    hostname = var.lxc_config.vm_name

    dynamic "ip_config" {
      for_each = var.lxc_config.ip_config
      content {
        ipv4 {
          address = ip_config.value.address
          gateway = ip_config.value.gateway
        }
      }
    }
  }

  operating_system {
    template_file_id = "local:vztmpl/nixos-base-lxc.tar.xz"
    type             = "nixos"
  }

  disk {
    datastore_id = "local-zfs"
    size         = var.lxc_config.disk_size
  }

  mount_point {
    volume = "/var/lib/pve/${var.lxc_config.vm_name}"
    path   = "/var/lib/nix-provisioning"
  }

  dynamic "mount_point" {
    for_each = var.mount_points
    content {
      volume = mount_point.value.volume
      size   = mount_point.value.size
      path   = mount_point.value.path
    }
  }


  startup {
    order      = var.lxc_config.startup.order
    up_delay   = var.lxc_config.startup.up_delay
    down_delay = var.lxc_config.startup.down_delay
  }

  protection = var.lxc_config.protection
}

# PVEのバックアップジョブを設定する
resource "proxmox_backup_job" "backup" {
  id       = "${var.lxc_config.vm_name}-backup"
  node     = var.lxc_config.node_name
  storage  = var.backup_config.storage_id
  schedule = var.backup_config.schedule
  vmid     = [tostring(proxmox_virtual_environment_container.lxc.vm_id)]
  mode     = "snapshot"
  compress = "zstd"

  prune_backups = {
    "keep-last"    = "7"
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "12"
  }
}
