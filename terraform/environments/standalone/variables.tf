variable "proxmox_endpoint" {
  type    = string
  default = "https://192.168.5.21:8006/api2/json"
}
variable "proxmox_username" {
  type      = string
  sensitive = true
}
variable "proxmox_password" {
  type      = string
  sensitive = true
}
