---
name: modify-terraform
description: Reference of directories, commands, and pitfalls for changing Terraform/Terragrunt resources (Proxmox VM/LXC, SDN, Talos, Cloudflare) in this repo.
---

# Terraform 資材の変更

Terraform / Terragrunt 資材を変更する際に使う手段・場所・注意点のカタログ。

## ディレクトリ対応表

| ディレクトリ | 管理対象 |
| :-- | :-- |
| `terraform/pve/hosts` | 物理ノードのブリッジ・VLAN・SDN Fabric (OSPF) |
| `terraform/pve/vm` | 旧セグメントの VM (oc1-omada) |
| `terraform/pve/hosts-secrets` | PVE ホストの `/var/lib/pve/<host>/` に LXC 向けシークレットファイル (sops-key, access-tokens-env) を配置 |
| `terraform/pbs` | Proxmox Backup Server (データストア等) |
| `terraform/vpc/cloudflare` | Cloudflare Tunnel・Zero Trust ポリシー |
| `terraform/vpc/zone-dev` | dev-server VM |
| `terraform/vpc/zone-private` | EVPN zone: private + prvmain VNet |
| `terraform/vpc/zone-private-k8s` | Talos クラスター・lb-1/2/3・egress-gateway・bluray-extractor 等 |
| `terraform/vpc/zone-private-persistent` | PostgreSQL LXC (pg-1/2/3) |
| `terraform/vpc/modules` | 共通モジュール (`k8s-cluster`, `lxc`, `nix-lxc`) |
| `terraform/truenas` | TrueNAS 設定 |

## 仕組み

- 各ゾーンの `terragrunt.hcl` は `find_in_parent_folders("root.hcl")` で `terraform/root.hcl` を include する
- `root.hcl` が `terraform/secrets.yaml` (SOPS) を復号して provider 設定 (`provider.tf`) を自動生成する。provider のバージョンも `root.hcl` で管理している
- state はローカル (`terraform.tfstate`)。リモートバックエンド未導入のため、state ファイルを壊す操作は厳禁

## よく使うコマンド

```bash
export PATH=$HOME/.nix-profile/bin:$PATH

# 差分確認
terragrunt --terragrunt-working-dir terraform/vpc/<zone> plan

# フォーマット・静的検証一式 (tflint + validate をダミーシークレットで実行)
bash scripts/validate-iac.sh
terragrunt hclfmt

# AI が実行してよいのはここまで
```

適用 (`apply`) は AGENTS.md のルールによりユーザーが実行する。plan 結果を添えて依頼する。

## IP アドレスの決め方・確認手段

- 割当済み IP は対象ゾーンの `.tf` ファイルを grep して重複がないか確認する
- SSH 接続用のホスト名 ↔ IP の対応は `.ssh/gen-keys.sh` が正 (詳細は AGENTS.md)
- 新規ホストを作ったら `.ssh/gen-keys.sh` の `NODES` にも追記する

## 注意点・既知の罠

- BGP EVPN Controller は Terraform 管理外。Proxmox GUI (Datacenter > SDN > Controllers) で手動管理
- LXC への SSH 公開鍵は `trimspace` 済みの `public_key_openssh` を渡す (`public_key_pem` ではない)
- NixOS LXC のシークレットファイル (sops-nix の Age 鍵・GitHub トークン) は `terraform/pve/hosts-secrets` が PVE ホストに配置し、`nix-lxc` モジュールが LXC 内の `/var/lib/nix-provisioning` に mount する。鍵関連の変更は [[sops-secrets]] を参照
