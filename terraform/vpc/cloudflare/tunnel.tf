variable "cloudflare_account_id" {
  type = string
}

resource "random_password" "tunnel_secret" {
  length  = 32
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "zero_trust_tunnel" {
  account_id = "${var.cloudflare_account_id}"
  name = "tunnel-common"
  config_src = "cloudflare"
  tunnel_secret = base64encode(random_password.tunnel_secret.result)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_route" "network_route" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.zero_trust_tunnel.id
  network    = "10.0.0.0/8"
}


resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "nuc-1"

  source_raw {
    file_name = "cloudflared-vm-config.yaml"
    data = <<EOF
#cloud-config
users:
  - default
  - name: ubuntu  # 必要に応じてユーザー名を変更してください
    groups: sudo
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh_authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJEI5oFS9EUqAUyW20Jy7YbJmLKcrS8DY8SB7KJe1bHo watanabekouhei@MacBook-Pro.local"

package_update: true
packages:
  - curl
runcmd:
  - curl -L --output /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
  - dpkg -i /tmp/cloudflared.deb
  # v5 では属性がないため、jsonencode と base64encode でトークンを自作する
  - cloudflared service install ${base64encode(jsonencode({
      "a" = var.cloudflare_account_id,
      "t" = cloudflare_zero_trust_tunnel_cloudflared.zero_trust_tunnel.id,
      "s" = base64encode(random_password.tunnel_secret.result)
    }))}
  - systemctl start cloudflared
  - sysctl -w net.ipv4.ip_forward=1
  - echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
EOF
  }
}

# 3. VM の定義 (サンプルをベースに修正)
resource "proxmox_virtual_environment_vm" "cloudflared_vm" {
  name      = "cloudflared-gateway-vm"
  node_name = "nuc-1"
  vm_id     = 1000

  cpu {
    cores = 1 # cloudflaredだけなら1コアで十分
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/noble-server-cloudimg-amd64.img"
    interface    = "scsi0"
    size         = 5
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.5.111/24"
        gateway = "192.168.5.1"
      }
    }
    ip_config {
      ipv4 {
        address = "10.30.1.244/24"
      }
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  network_device {
    bridge = "vmbr0"
  }
  network_device {
    bridge = "waaimain"
  }
}
