# ホストごとの SSH ホスト鍵 (scripts/gen-host-keys.sh が書く)
data "sops_file" "bluray_extractor_host_keys" {
  source_file = "${path.module}/../../pve/hosts-secrets/host-keys.yaml"
}


resource "proxmox_virtual_environment_file" "bluray_extractor_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "nuc-1"

  source_raw {
    file_name = "bluray-extractor-cloud-config.yaml"
    data      = <<EOF
#cloud-config
hostname: bluray-extractor
write_files:
  - path: /var/lib/nix-provisioning/ssh_host_ed25519_key
    permissions: '0600'
    owner: root:root
    content: |
      ${indent(6, trimspace(data.sops_file.bluray_extractor_host_keys.data["bluray-extractor"]))}
EOF
  }
}

resource "proxmox_virtual_environment_vm" "bluray_extractor" {
  name      = "bluray-extractor"
  node_name = "nuc-1"
  vm_id     = 240

  on_boot             = true
  reboot_after_update = false

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"
  efi_disk {
    datastore_id = "local-zfs"
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
    datastore_id = "local-zfs"
    ip_config {
      ipv4 {
        address = "10.20.1.80/24"
        gateway = "10.20.1.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.5.240/24"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.bluray_extractor_cloud_config.id
  }

  disk {
    datastore_id = "local-zfs"
    import_from  = "local:import/nixos-base-vm.qcow2"
    interface    = "virtio0"
    size         = 50
    aio          = "io_uring"
    cache        = "none"
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "prvmain"
    model  = "virtio"
    queues = 4
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    queues = 4
  }

  # USB Blu-ray ドライブのパススルー設定
  # host には VendorID:ProductID または 物理ポートを指定
  usb {
    host = "13fd:0840"
    usb3 = true
  }
}
