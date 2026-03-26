resource "proxmox_virtual_environment_vm" "proxmox_vm" {
  name      = "dev-server"
  node_name = "server-1"
  vm_id     = 1152

  machine = "q35"
  bios = "ovmf"
  efi_disk {
  }
  boot_order = [ "virtio0", "scsi0", "net0" ]

  cpu {
    cores = 16
    type = "host"
  }

  memory {
    dedicated = 32768
    floating  = 32768
  }

  initialization {
    ip_config {
        ipv4 {
          address = "192.168.5.199/24"
          gateway = "192.168.5.1"
        }
    }
    user_account {
      username = "nixos"
      keys     = [trimspace(data.local_file.id_rsa_pub.content)]
    }
  }

  disk {
    datastore_id = "local-zfs"
    file_id      = "local:iso/nixos.iso"
    interface    = "scsi0"
  }

  disk {
    datastore_id = "local-zfs"
    size         = 300
    interface    = "virtio0"
  }

  network_device {
    bridge = "vmbr0"
  }
}

data "local_file" "id_rsa_pub" {
  filename = "../../../.ssh/keys/dev-server.pub"
}
