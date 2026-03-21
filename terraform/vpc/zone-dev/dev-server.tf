resource "proxmox_virtual_environment_vm" "proxmox_vm" {
  name      = "dev-server"
  node_name = "server-1"
  vm_id     = 1152

  cpu {
    cores = 8
    type = "host"
  }

  memory {
    dedicated = 16384
    floating  = 16384
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
    size         = 100
    interface    = "virtio0"
  }

  network_device {
    bridge = "vmbr0"
  }
}

data "local_file" "id_rsa_pub" {
  filename = "../../../.ssh/keys/dev-server.pub"
}
