
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
  }
}
EOF
}

# ../../secrets.yaml を写した先でも解決できるよう、terraform/ の木ごと写して動かす (root.hcl と同じ理由)。
terraform {
  source = "${get_terragrunt_dir()}/../..//pve/hosts-secrets"
}

# ローカルステートを生成する
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/../../.state/pve/hosts-secrets/terraform.tfstate"
  }
}
