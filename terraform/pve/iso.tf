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

output "talos_schematic_id" {
  value = jsondecode(data.http.talos_schematic.response_body).id
}

resource "proxmox_virtual_environment_download_file" "talos_iscsi_image" {
  for_each = toset(["nuc-1", "nuc-2", "server-1"])

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key

  file_name = "talos-iscsi.iso"
  url       = "https://factory.talos.dev/image/${jsondecode(data.http.talos_schematic.response_body).id}/v1.12.2/nocloud-amd64.iso"
}

###

resource "proxmox_virtual_environment_download_file" "lxc_ubuntu_2504" {
  for_each     = toset(["nuc-1", "nuc-2", "server-1"])
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = each.key
  url          = "https://mirrors.servercentral.com/ubuntu-cloud-images/releases/25.04/release/ubuntu-25.04-server-cloudimg-amd64-root.tar.xz"
}
