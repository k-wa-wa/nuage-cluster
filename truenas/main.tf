
resource "truenas_dataset" "pool_1" {
  atime       = "OFF"
  compression = "LZ4"
  # full_path   = "/mnt/pool-1"
  # id          = "pool-1"
  # mount_path  = "/mnt/pool-1"
  quota       = "0"
  refquota    = "0"
}

resource "truenas_dataset" "pbs" {
  parent      = truenas_dataset.pool_1.id
  path        = "pbs"
  atime       = "OFF"
  compression = "LZ4"
}

resource "truenas_app" "pbs" {
  name       = "pbs"
  custom_app = true

  compose_config = <<-EOF
    services:
      pbs:
        image: dockurr/proxmox-backup:latest
        container_name: pbs
        environment:
          PASSWORD: "root"
          TZ: "Asia/Tokyo"
        ports:
          - "8007:8007"
        tmpfs:
          - /run
        volumes:
          - /mnt/pool-1/pbs/config:/etc/proxmox-backup
          - /mnt/pool-1/pbs/logs:/var/log/proxmox-backup
          - /mnt/pool-1/pbs/data:/var/lib/proxmox-backup
        restart: unless-stopped
        stop_grace_period: 2m
  EOF

  # データセット作成後にアプリをデプロイする
  depends_on = [truenas_dataset.pbs]
}
