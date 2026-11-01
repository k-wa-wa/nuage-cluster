variable "repo_root" {
  type        = string
  description = "リポジトリのルートの絶対パス。Proxmox に入る鍵 (.ssh/id_rsa) を読む"
}

variable "host" {
  type = string
}

variable "target_host" {
  type = string
}

variable "github_access_token" {
  type        = string
  description = "GitHub PAT for Nix to avoid API rate limits (read-only, public repos)"
  sensitive   = true
  default     = ""
}

variable "ssh_host_key" {
  type        = string
  description = "SSH のホスト鍵 (ed25519)。sops-nix の Age 鍵も兼ねる"
  sensitive   = true
}

variable "unprivileged" {
  type        = bool
  description = "配り先の LXC が非特権か (terraform/vpc の lxc_config.unprivileged と揃える)。true なら持ち主をコンテナの root (ホストの 100000:100000) にする"
  default     = false
}
