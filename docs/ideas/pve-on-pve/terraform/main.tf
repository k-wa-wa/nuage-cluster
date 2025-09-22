terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.80.0"
    }
  }
}

provider "proxmox" {
  insecure = true
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
}

resource "proxmox_virtual_environment_vm" "oc1-pve-1" {
  vm_id     = 2011
  name      = "oc1-pve-1"
  node_name = "server-1"
  started  = false

  cpu {
    cores = 4
  }

  memory {
    dedicated = 16384
    floating  = 16384
  }

  cdrom {
    file_id = "local:iso/proxmox-ve_9.0-1-auto-from-http.iso"
    interface = "ide2"
  }

  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size = 200
  }

  network_device {
    bridge = "vmbr2"
    mac_address = "0A:00:00:00:00:01"
  }
}

resource "proxmox_virtual_environment_vm" "oc1-pve-2" {
  vm_id     = 2012
  name      = "oc1-pve-2"
  node_name = "server-1"
  started  = false

  cpu {
    cores = 4
  }

  memory {
    dedicated = 16384
    floating  = 16384
  }

  cdrom {
    file_id = "local:iso/proxmox-ve_9.0-1-auto-from-http.iso"
    interface = "ide2"
  }

  disk {
    datastore_id = "local-zfs"
    interface    = "scsi0"
    size = 200
  }

  network_device {
    bridge = "vmbr2"
    mac_address = "0A:00:00:00:00:02"
  }
}
