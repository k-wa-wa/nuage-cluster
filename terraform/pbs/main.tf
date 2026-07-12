data "sops_file" "secrets" {
  source_file = "${path.module}/../secrets.yaml"
}

# データストア 'pbs' の定義
resource "pbs_datastore" "pbs" {
  name        = "pbs"
  path        = "/var/lib/proxmox-backup/pbs"
  comment     = "PBS backup datastore on TrueNAS"
  gc_schedule = "daily"
}
