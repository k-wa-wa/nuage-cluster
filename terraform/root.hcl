locals {
  common_secrets = read_terragrunt_config("${get_parent_terragrunt_dir()}/secrets.hcl")
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
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
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
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
