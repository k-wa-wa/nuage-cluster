# Proxmox のセットアップ

- zfs
    - 各ノードで zfs を作成する(local-zfs)
    - zfs の thin provision を有効化する(datacenter > storage > local-zfs)
- server-1 で仮想ブリッジを作成する
    - vmbr1: 192.168.1.0/24 と接続。Proxy で使用する。
    - vmbr10: IPは割り当てず、任意の物理NICに割り当てる。PVE on PVE で使用する。
