locals {
  secrets = yamldecode(sops_decrypt_file("${get_terragrunt_dir()}/secrets.yaml"))
}

# PBS用のプロバイダーを動的に生成する
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    truenas = {
      source  = "deevus/truenas"
      version = "0.16.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
  }
}

provider "truenas" {
  host        = "192.168.5.30"
  auth_method = "ssh"

  ssh {
    port                 = 22
    user                 = "${local.secrets.ssh_user}"
    private_key          = <<-EOT
${local.secrets.private_key}
EOT
    host_key_fingerprint = "${local.secrets.host_key_fingerprint}"
  }
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
