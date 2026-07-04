locals {
  common_secrets = read_terragrunt_config("${get_parent_terragrunt_dir()}/secrets.hcl")
  _block_deprecated = run_cmd(
    "sh", "-c",
    "echo '\n\u001b[1;31m[ERROR] secrets.hcl is no longer supported. Please migrate to root_sops.hcl.\u001b[0m\n' && exit 1"
  )
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

provider "proxmox" {
  insecure = true
  endpoint = "${local.common_secrets.inputs.proxmox_endpoint}"
  username = "${local.common_secrets.inputs.proxmox_username}"
  password = "${local.common_secrets.inputs.proxmox_password}"
  ssh {
    node {
      name    = "nuc-1"
      address = "192.168.5.21"
    }
    node {
      name    = "nuc-2"
      address = "192.168.5.22"
    }
    node {
      name    = "server-1"
      address = "192.168.5.25"
    }
  }
}

provider "cloudflare" {
  api_token = "${local.common_secrets.inputs.cloudflare_api_token}"
}
EOF
}

remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_parent_terragrunt_dir()}/${path_relative_to_include()}/terraform.tfstate"
  }
}
