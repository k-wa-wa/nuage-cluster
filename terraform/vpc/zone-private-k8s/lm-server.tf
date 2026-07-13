resource "proxmox_virtual_environment_vm" "lm_server" {
  name      = "lm-server"
  node_name = "server-2"
  vm_id     = 230
  # started   = false

  on_boot = false

  machine = "q35"
  bios    = "ovmf"
  efi_disk {
  }
  boot_order = ["virtio0", "net0"]

  cpu {
    cores = 4
    type  = "host"
  }

  memory {
    dedicated = 8192
    floating  = 8192
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.5.222/24" # TODO: server-2 にも SDN を引いたら prvmain に移行する
        gateway = "192.168.5.1"
      }
    }
  }

  disk {
    datastore_id = "local-thinpool"
    import_from  = "local:import/nixos-base-vm.qcow2"
    interface    = "virtio0"
    size         = 100
  }

  network_device {
    bridge = "vmbr0"
  }

  hostpci {
    device = "hostpci1"
    id     = "0000:05:00"
    pcie   = true
    xvga   = false
    rombar = true
  }
}

resource "proxmox_backup_job" "lm_server_backup" {
  id       = "lm-server-backup"
  node     = "server-2"
  storage  = "truenas-pbs"
  schedule = "daily"
  vmid     = [tostring(proxmox_virtual_environment_vm.lm_server.vm_id)]
  mode     = "snapshot"
  compress = "zstd"

  prune_backups = {
    "keep-last"    = "7"
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "12"
  }
}
