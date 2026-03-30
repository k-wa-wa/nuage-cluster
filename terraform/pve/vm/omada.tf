# __generated__ by OpenTofu
# Please review these resources and move them into your main configuration files.

# __generated__ by OpenTofu
resource "proxmox_virtual_environment_vm" "oc1-omada" {
  acpi                                 = true
  bios                                 = "seabios"
  boot_order                           = ["scsi0", "net0"]
  delete_unreferenced_disks_on_destroy = true
  description                          = ""
  hook_script_file_id                  = null
  // hotplug                              = null
  keyboard_layout                      = "en-us"
  kvm_arguments                        = ""
  mac_addresses                        = ["BC:24:11:07:AD:24", "BC:24:11:F9:AA:A6"]
  machine                              = ""
  migrate                              = false
  name                                 = "oc1-omada"
  node_name                            = "server-1"
  on_boot                              = true
  pool_id                              = ""
  protection                           = false
  purge_on_destroy                     = true
  reboot                               = false
  reboot_after_update                  = true
  scsi_hardware                        = "virtio-scsi-pci"
  started                              = true
  stop_on_destroy                      = false
  tablet_device                        = true
  tags                                 = []
  template                             = false
  timeout_clone                        = 1800
  timeout_create                       = 1800
  timeout_migrate                      = 1800
  timeout_reboot                       = 1800
  timeout_shutdown_vm                  = 1800
  timeout_start_vm                     = 1800
  timeout_stop_vm                      = 300
  vm_id                                = 1163
  cpu {
    // affinity     = ""
    architecture = ""
    cores        = 2
    flags        = []
    hotplugged   = 0
    limit        = 0
    numa         = false
    sockets      = 1
    type         = "host"
    units        = 1024
  }
  disk {
    aio               = "io_uring"
    backup            = true
    cache             = "none"
    datastore_id      = "local-zfs"
    discard           = "ignore"
    file_format       = "raw"
    file_id           = ""
    import_from       = ""
    interface         = "scsi0"
    iothread          = false
    path_in_datastore = "vm-1163-disk-0"
    replicate         = true
    serial            = ""
    size              = 20
    ssd               = false
  }
  initialization {
    datastore_id         = "local-lvm"
    // file_format          = ""
    interface            = "ide2"
    meta_data_file_id    = ""
    network_data_file_id = ""
    // type                 = ""
    user_data_file_id    = ""
    vendor_data_file_id  = ""
    ip_config {
      ipv4 {
        address = "192.168.5.163/24"
        gateway = "192.168.5.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.0.2/24"
        gateway = ""
      }
    }
    user_account {
      keys     = ["ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDwzrSbI1EIpqiSCOwadXe0C8rtz+udX73ZryEfft4RbDiEGEM5mjOf5t713G4N8ODj3o6itWnUM83B8j9w3h5xu+3DxdGtfVFCGbbNvaZxRLq3gZVOlwuWLmWArFBqtA4k1WwyHaMfbYqX6dGHFruMJ/VM+2paq1J+ilZRugNklvAMhq6FkXZMqkFGUBMaeSkhrVaDbv7XAT9RDIeMtD/pqnc4LcY9NmYHg6oR0aSuniwIJUSWhG9fRtbzK0DpXqcHsPEK1LpzCpX5vZGT6LfEDYZFLIIV7BbRlm5Gvr0vHi2zqNqdJiWHPwRtuOzlvCxArZ3gBSWW50F7rn6BAXWS+khnQ0RxBs2LTzTYdXa2qAqt/fQXQmEJ2TGXk7o5I8ENs4GUxL3GPk//kq869Lfj2kIOfykxgynnPfO6Pyh6uYzUVgQUQ6m5vp6mxZC0ADxaPFL0UGetHQz3ejtvFnuUyyczKkd2a0FoRHh9fvGMf3iZuZwBPTHtW7QDjPv5UINYcyjM+miijgYvv096WrlsI65a5mdAqvJf4zT4xQrC/9Z/pCUpgtri59JizfKgGGtijBEbZWPzwQEs3TlM9I/g6eA65TbSDwwUkJ0EPQ5OIp/e0rmkHzWy44vz2yaHkSSid6G9oCZhZVq1cDahct2Niht+dZBI1Vrx7QFuBdh7vQ== watanabekouhei@watanabekouheinoMacBook-Pro.local"]
      password = null # sensitive
      username = "ubuntu"
    }
  }
  memory {
    dedicated      = 4096
    floating       = 4096
    // hugepages      = ""
    keep_hugepages = false
    shared         = 0
  }
  network_device {
    bridge       = "vmbr0"
    disconnected = false
    enabled      = true
    firewall     = false
    mac_address  = "BC:24:11:07:AD:24"
    model        = "virtio"
    mtu          = 0
    queues       = 0
    rate_limit   = 0
    trunks       = ""
    vlan_id      = 0
  }
  network_device {
    bridge       = "vmbr999"
    disconnected = false
    enabled      = true
    firewall     = false
    mac_address  = "BC:24:11:F9:AA:A6"
    model        = "virtio"
    mtu          = 0
    queues       = 0
    rate_limit   = 0
    trunks       = ""
    vlan_id      = 0
  }
}
