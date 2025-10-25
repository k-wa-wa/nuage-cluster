module "load-balancer-01" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1051
    vm_name   = "load-balancer-01"
    node_name = "nuc-1"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.51/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 20
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "load-balancer-02" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1052
    vm_name   = "load-balancer-02"
    node_name = "nuc-2"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.52/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 20
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "control-plane-01" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1061
    vm_name   = "control-plane-01"
    node_name = "server-1"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.61/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 30
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "control-plane-02" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1062
    vm_name   = "control-plane-02"
    node_name = "nuc-1"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.62/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 30
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "control-plane-03" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1063
    vm_name   = "control-plane-03"
    node_name = "nuc-2"
    cores     = 2
    memory    = 4096
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.63/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 30
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "worker-node-01" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1071
    vm_name   = "worker-node-01"
    node_name = "server-1"
    cores     = 4
    memory    = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.71/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 100
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "worker-node-02" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1072
    vm_name = "worker-node-02"
    node_name = "nuc-1"
    cores     = 4
    memory    = 16384
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.72/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 100
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
module "worker-node-device-host-01" {
  source = "../../modules/ubuntu-vm"
  vm_config = {
    vm_id     = 1073
    vm_name = "worker-node-device-host-01"
    node_name = "nuc-2"
    cores     = 6
    memory    = 25476
    network_devices = [
      {
        bridge = "vmbr0"
      }
    ]
    ip_config = [
      {
        address = "192.168.5.83/24"
        gateway = "192.168.5.1"
      }
    ]
    ci_user   = "ubuntu"
    disk_size = 100
    usb_host  = "13fd:0840"
  }
  depends_on = [ proxmox_virtual_environment_download_file.ubuntu_cloud_image ]
}
