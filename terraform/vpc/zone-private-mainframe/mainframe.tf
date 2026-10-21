# メインフレーム (MVS 3.8j / MVS/CE を Hercules で常駐させる NixOS LXC)。
# 構成は nix/hosts/mainframe、用語と使い方は docs/mainframe.md を参照する。
#
# Hercules はユーザー空間のエミュレータで KVM を必要としないため LXC で足りる。
# MVS 3.8j は主記憶 16MB の世界であり、2 コア / 2GB で十分である。
# DASD (約 150MB) と nix store が載れば良いのでディスクは 20GB とする。
#
# DASD は rootfs 上の /var/lib/mainframe に置き、nix-lxc モジュールのバックアップジョブ
# (PBS, snapshot モード) で日次バックアップする。稼働中の snapshot なので
# クラッシュ整合となるが、趣味用途として許容する。
#
# LAN からの TN3270 は LB の VIP (192.168.5.200:3270) で中継するため、vmbr0 には足を出さない。
module "mainframe" {
  source = "../modules/nix-lxc"
  lxc_config = {
    vm_id     = 290
    vm_name   = "mainframe"
    node_name = "server-1"
    cores     = 2
    memory    = 2048
    network_devices = [
      {
        name   = "eth0"
        bridge = "dummy"
      },
      {
        name   = "eth1"
        bridge = "prvmain"
      }
    ]
    ip_config = [
      {
        address = "dhcp"
      },
      {
        address = "10.20.1.90/24"
        gateway = "10.20.1.1"
      }
    ]
    disk_size = 20
  }
}
