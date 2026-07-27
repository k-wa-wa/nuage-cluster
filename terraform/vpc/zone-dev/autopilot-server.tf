# nuage-autopilot の実行ホスト。
#
# lm-server / bluray-extractor と同じく base-vm の qcow2 イメージから起動する。
# cloud-init で hostname を渡すと、base-vm の nixos-bootstrap サービスが
# `nixos-rebuild switch --flake ...#<hostname>` を実行して構成を自動適用する。
# したがって cloud-config の hostname は nix/flake.nix の nixosConfigurations の
# キー (autopilot-server) と完全に一致させる必要がある。
#
# ネットワークは vmbr0 (192.168.5.0/24) のみとし、prvmain (SDN) には接続しない。
# 名前解決は lb の CoreDNS (VIP 192.168.5.200) を参照する。CoreDNS は cluster.wpc を
# ワイルドカードで 192.168.5.200 に解決するため、PR ごとに名前が変わる preview 環境
# (pechka-pr-<N>.cluster.wpc) にも到達できる。
#
# シークレット (GitHub / Claude / Antigravity のトークン) は SOPS で配布しない。
# 万一の流出時の影響が大きいため、VM 起動後に手作業で
# /var/lib/nuage-autopilot/secrets.env へ配置する運用とする。
# bluray-extractor のように cloud-config へ鍵を書き込むことは、ここでは意図的に行わない。

resource "proxmox_virtual_environment_file" "autopilot_server_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "server-1"

  source_raw {
    file_name = "autopilot-server-cloud-config.yaml"
    data      = <<EOF
#cloud-config
hostname: autopilot-server
EOF
  }
}

resource "proxmox_virtual_environment_vm" "autopilot_server" {
  name      = "autopilot-server"
  node_name = "server-1"
  vm_id     = 241

  on_boot = true

  machine = "q35"
  bios    = "ovmf"
  efi_disk {
  }
  boot_order = ["virtio0", "net0"]

  # LLM CLI がリポジトリのビルド・テストを回すため、ある程度の余裕を持たせる。
  cpu {
    cores = 8
    type  = "host"
  }

  memory {
    dedicated = 16384
    floating  = 16384
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.5.241/24"
        gateway = "192.168.5.1"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.autopilot_server_cloud_config.id
  }

  # リポジトリの clone、Go / Node のビルドキャッシュ、nix store のために確保する。
  disk {
    datastore_id = "local-zfs"
    import_from  = "local:import/nixos-base-vm.qcow2"
    interface    = "virtio0"
    size         = 100
  }

  network_device {
    bridge = "vmbr0"
  }
}

resource "proxmox_backup_job" "autopilot_server_backup" {
  id       = "autopilot-server-backup"
  node     = "server-1"
  storage  = "truenas-pbs"
  schedule = "daily"
  vmid     = [tostring(proxmox_virtual_environment_vm.autopilot_server.vm_id)]
  mode     = "snapshot"
  compress = "zstd"

  prune_backups = {
    "keep-last"    = "7"
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "12"
  }
}
