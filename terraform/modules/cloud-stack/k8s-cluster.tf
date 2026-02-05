resource "talos_machine_secrets" "this" {}

data "talos_machine_configuration" "this" {
  cluster_name     = var.cluster_config.cluster.name
  for_each         = var.cluster_config.nodes
  machine_type     = each.value.type
  cluster_endpoint = "https://${var.cluster_config.cluster.endpoint}:6443"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = [
    yamlencode({
      machine = {
        network = {
          nameservers = [
            "1.1.1.1",
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

resource "proxmox_virtual_environment_file" "talos_config_snippet" {
  for_each     = var.cluster_config.nodes
  content_type = "snippets"
  datastore_id = "local"
  node_name    = each.value.node_name

  source_raw {
    data      = data.talos_machine_configuration.this[each.key].machine_configuration
    file_name = "talos-${each.value.vm_name}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "cluster_vms" {
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
    file_id      = "local:iso/talos-nocloud-amd64.iso"
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
  }

  initialization {
    user_data_file_id = proxmox_virtual_environment_file.talos_config_snippet[each.key].id
  }
}

###

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_config.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.cluster_config.nodes : v.ip_address]
  endpoints            = [for k, v in var.cluster_config.nodes : v.ip_address]
}
