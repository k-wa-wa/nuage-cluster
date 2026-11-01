
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

# Proxmox に入る鍵 (.ssh/id_rsa) は terraform/ の外にあり写されないので、絶対パスで渡す。
# TODO: 変数をやめ、connection を ssh-agent (agent = true) にする。
inputs = {
  repo_root = get_repo_root()
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
