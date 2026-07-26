resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "local_file" "private_key_pem" {
  filename        = "${path.module}/ssh_key.pem"
  content         = tls_private_key.ssh_key.private_key_pem
  file_permission = "0400"
}

module "kafka-1" {
  depends_on = [
    proxmox_virtual_environment_sdn_applier.sdn_applier,
    proxmox_virtual_environment_sdn_vnet.main_services
  ]

  source = "../modules/lxc"
  lxc_config = {
    vm_id     = 401
    vm_name   = "kafka-1"
    node_name = "nuc-1"
    cores     = 2
    memory    = 8192
    network_devices = [
      {
        name   = "eth0"
        bridge = "waaimain"
      }
    ]
    ip_config = [
      {
        address = "10.30.1.11/24"
        gateway = "10.30.1.1"
      }
    ]
    disk_size       = 20
    ssh_public_keys = [tls_private_key.ssh_key.public_key_openssh]
  }
}
module "kafka-2" {
  depends_on = [
    proxmox_virtual_environment_sdn_applier.sdn_applier,
    proxmox_virtual_environment_sdn_vnet.main_services
  ]

  source = "../modules/lxc"
  lxc_config = {
    vm_id     = 402
    vm_name   = "kafka-2"
    node_name = "nuc-2"
    cores     = 2
    memory    = 8192
    network_devices = [
      {
        name   = "eth0"
        bridge = "waaimain"
      }
    ]
    ip_config = [
      {
        address = "10.30.1.12/24"
        gateway = "10.30.1.1"
      }
    ]
    disk_size       = 20
    ssh_public_keys = [tls_private_key.ssh_key.public_key_openssh]
  }
}
module "kafka-3" {
  depends_on = [
    proxmox_virtual_environment_sdn_applier.sdn_applier,
    proxmox_virtual_environment_sdn_vnet.main_services
  ]

  source = "../modules/lxc"
  lxc_config = {
    vm_id     = 403
    vm_name   = "kafka-3"
    node_name = "server-1"
    cores     = 2
    memory    = 8192
    network_devices = [
      {
        name   = "eth0"
        bridge = "waaimain"
      }
    ]
    ip_config = [
      {
        address = "10.30.1.13/24"
        gateway = "10.30.1.1"
      }
    ]
    disk_size       = 20
    ssh_public_keys = [tls_private_key.ssh_key.public_key_openssh]
  }
}
