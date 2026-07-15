variable "host" {
  type = string
}

variable "target_host" {
  type = string
}

variable "sops_key" {
  type        = string
  description = "The Age private key for sops-nix"
  sensitive   = true
  default     = ""
}

variable "github_access_token" {
  type        = string
  description = "GitHub PAT for Nix to avoid API rate limits (read-only, public repos)"
  sensitive   = true
  default     = ""
}
