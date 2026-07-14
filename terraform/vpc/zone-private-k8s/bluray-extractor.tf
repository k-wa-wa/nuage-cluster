data "sops_file" "bluray_extractor_secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

resource "proxmox_virtual_environment_file" "bluray_extractor_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "nuct-2"

  source_raw {
    file_name = "bluray-extractor-cloud-config.yaml"
    data      = <<EOF
#cloud-config
hostname: bluray-extractor
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
  node_name = "nuct-2"
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
    host = "13fd:0840"
    usb3 = true
  }
}
