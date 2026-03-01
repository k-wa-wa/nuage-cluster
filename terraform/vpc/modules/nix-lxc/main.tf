resource "proxmox_virtual_environment_file" "nixos_image" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = var.lxc_config.node_name

  source_file {
    file_name = "nixos-${var.lxc_config.vm_name}.tar.xz"
    path     = "../../../nix/result/tarball/nixos-system-x86_64-linux.tar.xz"
    checksum = filesha256("../../../nix/result/tarball/nixos-system-x86_64-linux.tar.xz")
  }
}

resource "proxmox_virtual_environment_container" "lxc" {
  node_name = var.lxc_config.node_name
  vm_id     = var.lxc_config.vm_id

  unprivileged = false
  features {
    nesting = true
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
    template_file_id = proxmox_virtual_environment_file.nixos_image.id
    type             = "nixos"
  }

  disk {
    datastore_id = "local-zfs"
    size         = var.lxc_config.disk_size
  }

  startup {
    order      = "3"
    up_delay   = "60"
    down_delay = "60"
  }

  protection = var.lxc_config.protection
}
