provider "kubernetes" {
  config_path = "../../playbooks/admin.conf"
}

variable "postgres_credentials_user" {
  type = string
}

variable "postgres_credentials_password" {
  type = string
}

resource "kubernetes_secret" "postgres-credentials" {
  metadata {
    name = "postgres-credentials"
  }

  data = {
    user = var.postgres_credentials_user
    password = var.postgres_credentials_password
  }

  type = "Opaque"
}

variable "grafana_credentials_service_account_token" {
  type = string
}

resource "kubernetes_secret" "name" {
  metadata {
    name = "grafana-credentials"
  }

  data = {
    service_account_token = var.grafana_credentials_service_account_token
  }
}