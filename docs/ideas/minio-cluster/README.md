# MinIO Cluster (退役アーカイブ)

## 概要

SeaweedFS (`swfs-cluster`, VIP: `10.20.1.60`) へのオブジェクトストレージ移行に伴い退役した、MinIO 分散クラスタ (`minio-cluster`) の設定アーカイブ。

## 構成情報

- **方式**: NixOS LXC × 2台 (`minio-cluster-1`, `minio-cluster-2`)
- **VIP**: `10.20.1.70` (keepalived による VRRP、ポート 9000)
- **ノードIP / VMID**:
  - `minio-cluster-1`: VMID 271, `10.20.1.71` (配置: nuc-1)
  - `minio-cluster-2`: VMID 272, `10.20.1.72` (配置: nuc-2 → 故障後 server-2 へ退避)
- **データ領域**: 各ノードに local-zfs 100GB × 2 ドライブ (`/data1`, `/data2`) をマウントし、計4ドライブで分散 erasure coding を構成

## ディレクトリ構成

- `terraform/`: Proxmox LXC 作成用および SOPS 鍵配布用の Terraform 定義
- `nix/`: MinIO サービス定義、keepalived VRRP 設定、flake.nix 定義スニペット
