module "oc1-devops" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1162
    vm_name = "oc1-devops"
    node_name = "server-1"
    cores = 4
    memory = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.162/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user = "ubuntu"
    disk_size = 200
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}

module "oc1-omada" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id = 1163
    vm_name = "oc1-omada"
    node_name = "server-1"
    cores = 2
    memory = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      },
      {
        bridge = "vmbr999"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.163/24"
        gateway = "192.168.5.1"
      },
      {
        address = "192.168.0.2/24"
      },
    ]
    ci_user = "ubuntu"
    disk_size = 20
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
