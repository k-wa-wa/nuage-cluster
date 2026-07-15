data "sops_file" "secrets" {
  source_file = "${path.module}/../../secrets.yaml"
}

module "lb-1" {
  source              = "./modules/secrets"
  host                = "192.168.5.21"
  target_host         = "lb-1"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "lb-2" {
  source              = "./modules/secrets"
  host                = "192.168.5.22"
  target_host         = "lb-2"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "lb-3" {
  source              = "./modules/secrets"
  host                = "192.168.5.25"
  target_host         = "lb-3"
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
  host                = "192.168.5.22"
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
  host                = "192.168.5.22"
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
module "minio-cluster-1" {
  source              = "./modules/secrets"
  host                = "192.168.5.21"
  target_host         = "minio-cluster-1"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
module "minio-cluster-2" {
  source              = "./modules/secrets"
  host                = "192.168.5.22"
  target_host         = "minio-cluster-2"
  sops_key            = data.sops_file.secrets.data["lb_sops_key"]
  github_access_token = data.sops_file.secrets.data["github_access_token"]
}
