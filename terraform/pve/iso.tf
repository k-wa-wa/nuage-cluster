resource "proxmox_virtual_environment_download_file" "talos_image" {
  for_each     = toset(["nuc-1", "nuc-2", "server-1"])
  content_type = "iso"
  datastore_id = "local"
  node_name    = each.key
  file_name    = "talos-nocloud-amd64.iso"
  url          = "https://factory.talos.dev/image/376567988ad370138ad8b2698212367b8edcb69b5fd68c80be1f2ec7d603b4ba/v1.12.2/nocloud-amd64.iso"
}
