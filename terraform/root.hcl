
locals {
  secrets = yamldecode(sops_decrypt_file("${get_parent_terragrunt_dir()}/secrets.yaml"))
}

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
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.111.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
  }
}

provider "proxmox" {
  insecure = true
  endpoint = "${local.secrets.proxmox_endpoint}"
  username = "${local.secrets.proxmox_username}"
  password = "${local.secrets.proxmox_password}"
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
