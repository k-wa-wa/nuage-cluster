data "sops_file" "secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

# PVEクラスター共通のPBSストレージ定義
resource "proxmox_storage_pbs" "truenas_pbs" {
  id          = "truenas-pbs"
  server      = "192.168.5.30"
  datastore   = "pbs"
  username    = data.sops_file.secrets.data["pbs_username"]
  password    = data.sops_file.secrets.data["pbs_password"]
  fingerprint = data.sops_file.secrets.data["pbs_fingerprint"]

  content = ["backup"]
}
