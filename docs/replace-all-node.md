# Proxmox ノードの replace 作業ログ

ルートファイルシステムを他ディスクにし、Ceph に移行したいため、各ノードに proxmox を 1 からインストールし直す。ついでに proxmox のバージョンを 8 → 9 にする

## データを維持したい VM を 1 つのマシンに寄せる

WebUI から手動で実施

## 他マシンの proxmox を新しいディスクにインストールし直す

### proxmox イメージの準備

あらかじめ公式から iso ファイルを取得しておく

```bash
diskutil list
diskutil unmountDisk /dev/<disk_id>

# r をつけることで I/O レイヤーのバッファリングをスキップして高速化
sudo dd if=$HOME/Downloads/proxmox-ve_9.0-1.iso of=/dev/r<disk_id> bs=1m

diskutil eject /dev/<disk_id>
```

### ノードをクラスターから除外

```bash
# server1
pvecm delnode <node_name>
```

WebUI からノードが見えなくなっていることを確認。ノード名が残り続ける場合には、以下で削除する

```bash
rm -rf /etc/pve/nodes/<node_name>
```

### ホストのバックアップ

```bash
# nfs をマウント
mount 192.168.5.151:/srv/nfs/backup /mnt

# ファイルシステムを tar.gz 化
sudo tar --exclude=/home --exclude=/var --exclude=/mnt --exclude=/media --exclude=/dev --exclude=/proc --exclude=/sys --exclude=/run --exclude=/tmp --exclude=/lost+found -cvpzf /mnt/backup.tar.gz /
```

### Proxmox を再インストール

1. USB デバイスからインストール
1. 既存クラスターに参加

## 新しいノードで Ceph を構築する

WebUI から手動で実施。Proxmox 8 と 9 が同じクラスターにいると、Ceph の構築時にエラーが出たため、VM を退避したノードは退避してから実施した。

Ceph のインストール・Monitor の追加・OSD の追加・プールの作成(ceph-pool-1) を実施。

## そのほか試したこと

### VM をバックアップ

```bash
# apt install -y nfs-common
mount 192.168.5.151:/srv/nfs/backup /mnt
vzdump <vmid> --dumpdir /mnt --compress zstd
```
