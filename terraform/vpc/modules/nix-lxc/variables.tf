variable "lxc_config" {
  type = object({
    vm_id     = number
    vm_name   = string
    node_name = string
    cores     = number
    memory    = number
    network_devices = list(object({
      name   = string
      bridge = string
    }))
    ip_config = list(object({
      address = string // with mask
      gateway = optional(string)
    }))
    disk_size = number // GB
    usb = optional(list(object({
      host = string
    })))
    protection = optional(bool)
    // true で非特権 LXC にする (コンテナの root はホストの UID 100000 に当たる)。
    // 既定は特権のままにし、未指定の LXC が作り直されないようにする。
    unprivileged = optional(bool, false)
    // true で /var/lib/nix-provisioning (ホストの /var/lib/pve/<vm_name>) を読み取り専用で mount する。
    // 既定の false は bpg provider の read_only の既定値と同じで、未指定の LXC は差分が出ない。
    // mount_point は ForceNew なので、変えると LXC は作り直しになる。
    provisioning_read_only = optional(bool, false)
    startup = optional(object({
      order      = string
      up_delay   = string
      down_delay = string
      }), {
      order      = "3"
      up_delay   = "10"
      down_delay = "15"
    })
  })
}

variable "mount_points" {
  type = list(object({
    volume = string
    size   = optional(string)
    path   = string
  }))
  default = []
}

variable "backup_config" {
  type = object({
    storage_id = optional(string, "truenas-pbs")
    schedule   = optional(string, "daily")
  })
  default = {
    storage_id = "truenas-pbs"
    schedule   = "daily"
  }
}
