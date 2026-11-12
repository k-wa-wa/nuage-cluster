# atelier: エージェントと一緒に開発する作業場 (Orca サーバー + autopilot5)。
#
# lm-server / bluray-extractor と同じく base-vm の qcow2 イメージから起動する。
# cloud-init で hostname を渡すと、base-vm の nixos-bootstrap サービスが
# `nixos-rebuild switch --flake ...#<hostname>` を実行して構成を自動適用する。
# したがって cloud-config の hostname は nix/flake.nix の nixosConfigurations の
# キー (atelier) と完全に一致させる必要がある。
#
# ネットワークは prvmain (SDN: 10.20.1.0/24) と vmbr0 (LAN: 192.168.5.0/24) の 2 本。
# 既定経路は prvmain 側に置き、LAN 側は家の中の Mac から踏み台なしで入るために使う。
# 外 (出先のスマホ・Mac) からは、別サーバーの Tailscale (subnet router) 経由で LAN 側に入る。
#
# シークレット (GitHub の bot token、Claude / Antigravity / Codex のログイン) は SOPS で配布しない。
# 万一の流出時の影響が大きいため、VM 起動後に手作業で配置・ログインする運用とする。
# ただし SSH のホスト鍵だけは cloud-config で渡す。sops-nix がこの鍵で nix/hosts/atelier/secrets.yaml を開くので、
# VM を作り直しても同じ鍵で戻るようにする (bluray-extractor と同じ)。

# ホストごとの SSH ホスト鍵 (scripts/gen-host-keys.sh が書く)
data "sops_file" "atelier_host_keys" {
  source_file = "${path.module}/../../pve/hosts-secrets/host-keys.yaml"
}

resource "proxmox_virtual_environment_file" "atelier_cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "server-1"

  source_raw {
    file_name = "atelier-cloud-config.yaml"
    data      = <<EOF
#cloud-config
hostname: atelier
write_files:
  - path: /var/lib/nix-provisioning/ssh_host_ed25519_key
    permissions: '0600'
    owner: root:root
    content: |
      ${indent(6, trimspace(data.sops_file.atelier_host_keys.data["atelier"]))}
EOF
  }
}

resource "proxmox_virtual_environment_vm" "atelier" {
  name      = "atelier"
  node_name = "server-1"
  vm_id     = 252

  on_boot             = true
  reboot_after_update = false

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-single"
  efi_disk {
  }
  boot_order = ["virtio0", "net0"]

  # 複数のワークスペースでエージェントが並行してビルド・テストを回すため、余裕を持たせる。
  cpu {
    cores = 8
    type  = "host"
    numa  = true
  }

  memory {
    dedicated = 16384
    floating  = 16384
  }

  initialization {
    ip_config {
      ipv4 {
        address = "10.20.1.52/24"
        gateway = "10.20.1.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.5.252/24"
      }
    }
    user_data_file_id = proxmox_virtual_environment_file.atelier_cloud_config.id
  }

  # ワークスペース (git worktree)、Go / Node のビルドキャッシュ、nix store のために確保する。
  disk {
    datastore_id = "local-zfs"
    import_from  = "local:import/nixos-base-vm.qcow2"
    interface    = "virtio0"
    size         = 150
    aio          = "io_uring"
    cache        = "none"
    discard      = "on"
    iothread     = true
  }

  network_device {
    bridge = "prvmain"
    model  = "virtio"
    queues = 8
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
    queues = 8
  }

  # cloud-config を変えると VM の作り直しになる。atelier にはワークスペースやログインの状態があるので、
  # 動いている VM には cloud-config の変更を当てない。cloud-config は VM を新しく作るときにだけ効く。
  lifecycle {
    ignore_changes = [initialization[0].user_data_file_id]
  }
}

resource "proxmox_backup_job" "atelier_backup" {
  id       = "atelier-backup"
  node     = "server-1"
  storage  = "truenas-pbs"
  schedule = "daily"
  vmid     = [tostring(proxmox_virtual_environment_vm.atelier.vm_id)]
  mode     = "snapshot"
  compress = "zstd"

  prune_backups = {
    "keep-last"    = "7"
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "12"
  }
}
