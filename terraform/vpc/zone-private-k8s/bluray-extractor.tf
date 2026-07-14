data "sops_file" "bluray_extractor_secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

resource "proxmox_virtual_environment_file" "bluray_extractor_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "server-2"

  source_raw {
    file_name = "bluray-extractor-cloud-config.yaml"
    data = <<EOF
#cloud-config
write_files:
  - path: /var/lib/sops-nix/key.txt
    permissions: '0600'
    owner: root:root
    content: |
      ${data.sops_file.bluray_extractor_secrets.data["lb_sops_key"]}
EOF
  }
}

resource "proxmox_virtual_environment_vm" "bluray_extractor" {
  name      = "bluray-extractor"
  node_name = "server-2"
  vm_id     = 240

  on_boot = true

  machine = "q35"
  bios    = "ovmf"
  efi_disk {
  }
  boot_order = ["virtio0", "net0"]

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 4096
    floating  = 4096
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.5.240/24"
        gateway = "192.168.5.1"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.bluray_extractor_cloud_config.id
  }

  disk {
    datastore_id = "local-thinpool"
    import_from  = "local:import/nixos-base-vm.qcow2"
    interface    = "virtio0"
    size         = 50
  }

  network_device {
    bridge = "vmbr0"
  }

  # USB Blu-ray ドライブのパススルー設定
  # host には VendorID:ProductID または 物理ポートを指定
  usb {
    host = "05ac:8300"
    usb3 = true
  }
}

resource "proxmox_backup_job" "bluray_extractor_backup" {
  id       = "bluray-extractor-backup"
  node     = "server-2"
  storage  = "truenas-pbs"
  schedule = "daily"
  vmid     = [tostring(proxmox_virtual_environment_vm.bluray_extractor.vm_id)]
  mode     = "snapshot"
  compress = "zstd"

  prune_backups = {
    "keep-last"    = "7"
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "12"
  }
}
