variable "repo_root" {
  type        = string
  description = "リポジトリのルートの絶対パス (terragrunt.hcl が渡す)"
}

data "sops_file" "secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

# ホストごとの SSH ホスト鍵 (scripts/gen-host-keys.sh が書く)
data "sops_file" "host_keys" {
  source_file = "${path.module}/host-keys.yaml"
}

module "lb-1" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.21"
  target_host         = "lb-1"
  unprivileged        = true
  ssh_host_key        = data.sops_file.host_keys.data["lb-1"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "lb-2" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.26"
  target_host         = "lb-2"
  unprivileged        = true
  ssh_host_key        = data.sops_file.host_keys.data["lb-2"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "lb-3" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.25"
  target_host         = "lb-3"
  unprivileged        = true
  ssh_host_key        = data.sops_file.host_keys.data["lb-3"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "egress-gateway" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.25"
  target_host         = "egress-gateway"
  ssh_host_key        = data.sops_file.host_keys.data["egress-gateway"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "chaos-monitor" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.26"
  target_host         = "chaos-monitor"
  ssh_host_key        = data.sops_file.host_keys.data["chaos-monitor"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "pg-cluster-1" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.21"
  target_host         = "pg-cluster-1"
  ssh_host_key        = data.sops_file.host_keys.data["pg-cluster-1"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "pg-cluster-2" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.26"
  target_host         = "pg-cluster-2"
  ssh_host_key        = data.sops_file.host_keys.data["pg-cluster-2"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "pg-cluster-3" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.25"
  target_host         = "pg-cluster-3"
  ssh_host_key        = data.sops_file.host_keys.data["pg-cluster-3"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "mainframe" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.25"
  target_host         = "mainframe"
  ssh_host_key        = data.sops_file.host_keys.data["mainframe"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "swfs-cluster-1" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.21"
  target_host         = "swfs-cluster-1"
  ssh_host_key        = data.sops_file.host_keys.data["swfs-cluster-1"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "swfs-cluster-2" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.26"
  target_host         = "swfs-cluster-2"
  ssh_host_key        = data.sops_file.host_keys.data["swfs-cluster-2"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "swfs-cluster-3" {
  source              = "./modules/secrets"
  repo_root           = var.repo_root
  host                = "192.168.5.25"
  target_host         = "swfs-cluster-3"
  ssh_host_key        = data.sops_file.host_keys.data["swfs-cluster-3"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
