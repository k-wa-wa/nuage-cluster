locals {
  secrets = yamldecode(sops_decrypt_file("${get_terragrunt_dir()}/../secrets.yaml"))
}

# ../secrets.yaml を写した先でも解決できるよう、terraform/ の木ごと写して動かす (root.hcl と同じ理由)。
terraform {
  source = "${get_terragrunt_dir()}/..//pbs"
}

# PBS用のプロバイダーを動的に生成する
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    sops = {
      source = "carlpett/sops"
      version = "1.4.1"
    }
    pbs = {
      source  = "registry.terraform.io/mcfitz2/pbs"
      version = "0.2.1"
    }
  }
}

provider "pbs" {
  endpoint = "https://192.168.5.30:8007"
  insecure = true
  username = "${local.secrets.pbs_username}"
  password = "${local.secrets.pbs_password}"
}
EOF
}

# ローカルステートを生成する
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/../.state/pbs/terraform.tfstate"
  }
}
