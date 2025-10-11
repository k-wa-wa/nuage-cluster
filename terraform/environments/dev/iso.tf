variable "pve_nodes" {
  type = list(string)
  default = [ "nuc-1", "nuc-2", "server-1" ]
}

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each = toset(var.pve_nodes)

  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value

  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}
