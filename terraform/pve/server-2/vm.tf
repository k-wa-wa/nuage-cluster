resource "proxmox_virtual_environment_vm" "proxmox_vm" {
  name      = "lm-server"
  node_name = "server-2"
  vm_id     = 200

  on_boot = false

  machine = "q35"
  bios = "ovmf"
  efi_disk {
  }
  boot_order = [ "virtio0", "scsi0", "net0" ]

  cpu {
    cores = 4
    type = "host"
  }

  memory {
    dedicated = 8192
    floating  = 8192
  }

  initialization {
    ip_config {
        ipv4 {
          address = "192.168.5.222/24"
          gateway = "192.168.5.1"
        }
    }
    user_account {
      username = "ubuntu"
      keys     = [trimspace(data.local_file.id_rsa_pub.content)]
    }
  }

  disk {
    datastore_id = "local-thinpool"
    file_id      = "local:iso/nixos.iso"
    interface    = "scsi0"
  }

  disk {
    datastore_id = "local-thinpool"
    size         = 100
    interface    = "virtio0"
  }

  network_device {
    bridge = "vmbr0"
  }

  hostpci {
    device = "hostpci0"
    id = "0000:12:00"
    pcie = true
    xvga = true
    rombar = true
  }
  hostpci {
    device   = "hostpci1"
    id       = "0000:05:00"
    pcie     = true
    xvga     = false
    rombar   = true
  }
}

data "local_file" "id_rsa_pub" {
  filename = "../../../.ssh/id_rsa.pub"
}
