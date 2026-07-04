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

data "sops_file" "secrets" {
  source_file = "${path.module}/secrets.yaml"
}

provider "truenas" {
  host        = "192.168.5.30"
  auth_method = "ssh"

  ssh {
    port                 = 22
    user                 = "root"
    private_key          = data.sops_file.secrets.data["private_key"]
    host_key_fingerprint = "SHA256:x7Vm5YgPI/wWy3BNpCxQCn3mTuQPT4gKziktdBLRrq8"
  }
}
