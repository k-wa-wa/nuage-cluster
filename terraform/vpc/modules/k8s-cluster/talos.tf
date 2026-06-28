data "http" "talos_schematic" {
  url    = "https://factory.talos.dev/schematics"
  method = "POST"
  request_headers = {
    "Content-Type" = "application/json"
  }
  request_body = jsonencode({
    customization = {
      systemExtensions = {
        officialExtensions = ["siderolabs/iscsi-tools", "siderolabs/util-linux-tools"]
      }
      extraKernelArgs = [
      ]
    }
  })
}

data "http" "talos_schematic_auto" {
  url    = "https://factory.talos.dev/schematics"
  method = "POST"
  request_headers = {
    "Content-Type" = "application/json"
  }
  request_body = jsonencode({
    customization = {
      systemExtensions = {
        officialExtensions = ["siderolabs/iscsi-tools", "siderolabs/util-linux-tools"]
      }
      extraKernelArgs = [
        "talos.config.autoBootstrap=true"
      ]
    }
  })
}

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "this" {
  cluster_name     = var.cluster_config.cluster.name
  for_each         = var.cluster_config.nodes
  machine_type     = each.value.type
  cluster_endpoint = "https://${var.cluster_config.cluster.endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = "v1.12"

  config_patches = [
    yamlencode({
      machine = {
        # 自律的にディスクへのインストールを実行させる設定
        install = {
          image = each.key == "controlplane-01" ? "factory.talos.dev/installer/${jsondecode(data.http.talos_schematic_auto.response_body).id}:v1.12.2" : "factory.talos.dev/installer/${jsondecode(data.http.talos_schematic.response_body).id}:v1.12.2"
          disk  = "/dev/sda"
          grubUseUKICmdline = false
          extraKernelArgs = each.key == "controlplane-01" ? [
            "talos.config.autoBootstrap=true"
          ] : []
        }
        kubelet = {
          nodeIP = {
            validSubnets = ["${var.cluster_config.cluster.node_subnet}"]
          }
          extraArgs = {
            "node-ip" = each.value.ip_address
          }
          extraMounts = [
            {
              destination = "/var/lib/longhorn"
              type        = "bind"
              source      = "/var/lib/longhorn"
              options     = ["bind", "rshared"]
            }
          ]
        }
        network = {
          # インストーラーダウンロードのためのDNSサーバーを静的指定
          nameservers = [
            var.cluster_config.cluster.gateway,
            "8.8.8.8"
          ]
          interfaces = [
            {
              interface = "ens18",
              addresses = ["${each.value.ip_address}/${each.value.cidr}"],
              routes = [
                {
                  network = "0.0.0.0/0"
                  gateway = var.cluster_config.cluster.gateway
                }
              ]
              vip = each.value.type == "controlplane" ? {
                ip = var.cluster_config.cluster.endpoint
              } : null
            }
          ]
        }
        time = {
          servers = ["/dev/ptp0"]
        }
        kernel = {
          modules = [{ name = "iscsi_tcp" }]
        }
        # lb-1 HAProxy 経由で talosctl を使用するため、
        # Talos API 証明書の SAN に lb-1 の IP を追加
        certSANs = [
          "192.168.5.200",
          "192.168.5.201",
          each.value.ip_address
        ]
      }
      cluster = {
        network       = { cni = { name = "none" } }
        proxy         = { disabled = true }
        apiServer = {
          # lb-1 経由での kubectl アクセスに必要な SAN
          certSANs = [
            "192.168.5.200",
            "192.168.5.201",
            var.cluster_config.cluster.endpoint
          ]
        }
      }
    })
  ]
}

resource "proxmox_virtual_environment_file" "talos_config_snippet" {
  for_each     = var.cluster_config.nodes
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.node_name

  source_raw {
    data      = data.talos_machine_configuration.this[each.key].machine_configuration
    file_name = "talos-${each.value.vm_id}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "cluster_vms" {
  for_each = var.cluster_config.nodes

  vm_id     = each.value.vm_id
  name      = "${var.cluster_config.cluster.name}-${each.key}"
  node_name = each.value.node_name

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
  }

  boot_order = [ "scsi0", "scsi3" ]

  # システム用ディスク (sda)
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size         = each.value.disk_size
  }
  # データ用の空ディスク (sdb)
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi1"
    size         = each.value.disk_size
  }
  # インストール用のISOファイル
  cdrom {
    file_id   = "local:iso/talos-iscsi.iso"
    interface = "scsi3"
  }

  # 内部SDNブリッジ (prvmain) のみのシングルNIC構成
  network_device {
    bridge = each.value.bridge
  }

  initialization {
    type              = "nocloud"
    datastore_id      = "local-zfs"
    user_data_file_id = proxmox_virtual_environment_file.talos_config_snippet[each.key].id
  }
}

# ローカルデバッグ用に talosconfig のみを静的生成して出力 (VMへの接続は不要)
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_config.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.cluster_config.nodes : v.ip_address]
  endpoints            = [for k, v in var.cluster_config.nodes : v.ip_address]
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.root}/talosconfig-${var.cluster_config.cluster.name}"
}
