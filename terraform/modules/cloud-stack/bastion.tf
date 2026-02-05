resource "random_password" "bastion_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "proxmox_virtual_environment_file" "bastion_cloud_init" {
  depends_on   = [data.talos_client_configuration.this]
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.bastion_config.node_name

  source_raw {
    file_name = "bastion-config.yaml"

    data = <<-EOT
    #cloud-config
    password: ${bcrypt(random_password.bastion_password.result)}
    chpasswd: { expire: False }
    ssh_pwauth: true

    write_files:
      - path: /home/ubuntu/.talos/config
        content: ${base64encode(data.talos_client_configuration.this.talos_config)}
        encoding: b64
        permissions: '0644'
    package_update: true

    runcmd:
      - curl -sL https://talos.dev/install | sh
      - wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
      - apt install ./cloudflared-linux-amd64.deb
      - echo "Provisioning finished at $(date)" >> /var/log/provision.log
    EOT
  }
}

resource "proxmox_virtual_environment_vm" "bastion_vm" {
  vm_id     = var.bastion_config.vm_id
  name      = "bastion-${var.bastion_config.vm_id}"
  node_name = var.bastion_config.node_name

  cpu {
    cores = 1
    type  = "host"
  }

  memory {
    dedicated = 4096
    floating  = 4096
  }

  initialization {
    user_data_file_id = resource.proxmox_virtual_environment_file.bastion_cloud_init.id

    ip_config {
      ipv4 {
        address = var.bastion_config.ip_address
        gateway = var.bastion_config.gateway
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.5.170/24"
      }
    }
    user_account {
      username = "ubuntu"
    }
  }

  disk {
    datastore_id = "local-zfs"
    file_id      = "local:iso/noble-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = 40
  }

  network_device {
    bridge = var.bastion_config.bridge
  }
  network_device {
    bridge = var.bastion_config.enable_access_from_private_network ? "vmbr0" : null
  }
}
