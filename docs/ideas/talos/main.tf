###

data "http" "talos_schematic" {
  for_each = var.cluster_config.nodes
  url      = "https://factory.talos.dev/schematics"
  method   = "POST"
  request_headers = {
    "Content-Type" = "application/json"
  }
  # ここでノードごとの設定（IPなど）を動的に流し込む
  request_body = jsonencode({
    customization = {
      # systemExtensions = {
      #   officialExtensions = ["siderolabs/qemu-guest-agent"]
      # }
      extraKernelArgs = [
        # ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:<dns0-ip>:<dns1-ip>:<ntp0-ip>
        "ip=${each.value.ip_address}:${each.value.ip_address}:${var.cluster_config.cluster.gateway}:${each.value.cidr}:${each.value.vm_name}:ens18:off:8.8.8.8"
      ]
    }
  })
}

resource "proxmox_virtual_environment_download_file" "talos_image" {
  for_each = var.cluster_config.nodes

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value.node_name

  file_name = "talos-${each.value.vm_name}.iso"
  url       = "https://factory.talos.dev/image/${jsondecode(data.http.talos_schematic[each.key].response_body).id}/v1.12.2/nocloud-amd64.iso"
}

resource "proxmox_virtual_environment_vm" "cluster_vms" {
  depends_on = [proxmox_virtual_environment_download_file.talos_image]
  for_each   = var.cluster_config.nodes

  vm_id     = each.value.vm_id
  name      = each.value.vm_name
  node_name = each.value.node_name

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
    floating  = each.value.memory
  }

  disk {
    datastore_id = "local-zfs"
    file_id      = "local:iso/talos-${each.value.vm_name}.iso"
    interface    = "scsi0"
    size         = each.value.disk_size
  }
  disk {
    datastore_id = "local-zfs"
    interface    = "scsi1"
    size         = each.value.disk_size
  }

  network_device {
    bridge      = each.value.bridge
    mac_address = each.value.mac_address
  }
}

###

resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "this" {
  cluster_name     = var.cluster_config.cluster.name
  for_each         = var.cluster_config.nodes
  machine_type     = each.value.type
  cluster_endpoint = "https://${var.cluster_config.cluster.endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
}

# 3. 起動したVMに対して設定を適用（ここが重要）
resource "talos_machine_configuration_apply" "this" {
  depends_on = [proxmox_virtual_environment_vm.cluster_vms]
  for_each   = var.cluster_config.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  endpoint                    = each.value.ip_address
  node                        = each.value.ip_address

  config_patches = [
    yamlencode({
      machine = {
        network = {
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
            }
          ]
        }
        time = {
          servers = ["/dev/ptp0"]
        }
      }
      cluster = {
        network = { cni = { name = "none" } }
        proxy   = { disabled = true }
      }
    })
  ]
}

###

resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoint             = [for k, v in var.cluster_config.nodes : v.ip_address if v.type == "controlplane"][0]
  node                 = [for k, v in var.cluster_config.nodes : v.ip_address if v.type == "controlplane"][0]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = [for k, v in var.cluster_config.nodes : v.ip_address if v.type == "controlplane"][0]
}

resource "local_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/kubeconfig"
}


# talosconfig を生成するためのデータソース
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_config.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.cluster_config.nodes : v.ip_address]
  endpoints            = [for k, v in var.cluster_config.nodes : v.ip_address if v.type == "controlplane"]
}

resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talosconfig"
}
