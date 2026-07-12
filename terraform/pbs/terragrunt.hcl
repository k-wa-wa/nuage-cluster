locals {
  secrets = yamldecode(sops_decrypt_file("${get_terragrunt_dir()}/../secrets.yaml"))
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
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}
