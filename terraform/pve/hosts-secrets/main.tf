data "sops_file" "secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

# host は LXC が載っている PVE ノードの管理 IP である。
# nuc-1 = 192.168.5.21、server-1 = 192.168.5.25、server-2 = 192.168.5.26。
# unprivileged は terraform/vpc の lxc_config.unprivileged と揃える。
module "lb-1" {
  source              = "./modules/secrets"
  host                = "192.168.5.21"
  target_host         = "lb-1"
  unprivileged        = true
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "lb-2" {
  source              = "./modules/secrets"
  host                = "192.168.5.26"
  target_host         = "lb-2"
  unprivileged        = true
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "lb-3" {
  source              = "./modules/secrets"
  host                = "192.168.5.25"
  target_host         = "lb-3"
  unprivileged        = true
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "egress-gateway" {
  source              = "./modules/secrets"
  host                = "192.168.5.25"
  target_host         = "egress-gateway"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "chaos-monitor" {
  source              = "./modules/secrets"
  host                = "192.168.5.26"
  target_host         = "chaos-monitor"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "pg-cluster-1" {
  source              = "./modules/secrets"
  host                = "192.168.5.21"
  target_host         = "pg-cluster-1"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "pg-cluster-2" {
  source              = "./modules/secrets"
  host                = "192.168.5.26"
  target_host         = "pg-cluster-2"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "pg-cluster-3" {
  source              = "./modules/secrets"
  host                = "192.168.5.25"
  target_host         = "pg-cluster-3"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "mainframe" {
  source              = "./modules/secrets"
  host                = "192.168.5.25"
  target_host         = "mainframe"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "swfs-cluster-1" {
  source              = "./modules/secrets"
  host                = "192.168.5.21"
  target_host         = "swfs-cluster-1"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "swfs-cluster-2" {
  source              = "./modules/secrets"
  host                = "192.168.5.26"
  target_host         = "swfs-cluster-2"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "swfs-cluster-3" {
  source              = "./modules/secrets"
  host                = "192.168.5.25"
  target_host         = "swfs-cluster-3"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
