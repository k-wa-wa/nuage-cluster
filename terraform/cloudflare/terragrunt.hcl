locals {
  has_local_secrets = fileexists("${get_terragrunt_dir()}/secrets.local.yaml")
  local_secrets     = local.has_local_secrets ? yamldecode(file("${get_terragrunt_dir()}/secrets.local.yaml")) : {}
  cloudflare_token  = try(local.local_secrets.cloudflare_api_token, "")
}

# Cloudflare プロバイダーと Random プロバイダーを動的に生成
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.22.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "cloudflare" {
%{if local.cloudflare_token != ""~}
  api_token = "${local.cloudflare_token}"
%{endif~}
}
EOF
}

# ローカルステートの設定
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/../.state/cloudflare/terraform.tfstate"
  }
}
