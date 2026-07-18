# nuage-cluster  :sun_behind_small_cloud:

おうちクラスターのセットアップリポジトリ

TODO・改善アイディア・過去の設計判断の経緯は [TODO.md](./TODO.md) にまとめている。

## アーキテクチャ

![全体構成図](./docs/architecture-overview.drawio.svg)

- **仮想化基盤**: Proxmox VE
- **ネットワーク**: Proxmox SDN
- **Kubernetes**: Talos, Cilium, ArgoCD
- **ロードバランサー**: HAProxy + keepalived + CoreDNS
- **データストア**: PostgreSQL, NFS, Minio
- **VPN**: Tailscale, Cloudflare Tunnel + Zero Trust
- **シークレット管理**: SOPS + Age

詳細なアーキテクチャ図・リソース一覧(IP / VMID)は [docs/architecture.md](./docs/architecture.md) を参照。

## 管理レイヤー (IaC / GitOps)

管理レイヤーは 3 層あり、いずれも本リポジトリを起点とする。

| 層 | ツール | 対象 | 適用方法 |
| :-- | :-- | :-- | :-- |
| ① インフラ | Terragrunt + OpenTofu | SDN・VM・LXC・Talos マシン設定・Cloudflare Tunnel | ローカルから `terragrunt apply` (手動 Push 型) |
| ② OS | Nix Flake + nixos-generators + sops-nix | NixOS LXC / VM | LXC は `system.autoUpgrade` による自動 Pull。一部 `nixos-rebuild switch --flake` で手動 Push |
| ③ アプリ | Argo CD (ApplicationSet + Kustomize + SOPS プラグイン) | Kubernetes 上の全アプリ | master ブランチへの push で自動同期 |

Argo CD は `manifests/apps/*/overlays/prod` を自動検出して同名 namespace にデプロイし、外部リポジトリのアプリも `multi-repo-deploy.yaml` でまとめて管理する。

## ディレクトリ構成

```
.
├── terraform/      # ① インフラ層 (Terragrunt + OpenTofu)
│   ├── vpc/        #   SDN ゾーンごとの構成 (zone-private-k8s, cloudflare など)
│   └── pve/        #   Proxmox ホスト・VM 定義
├── nix/            # ② OS 層 (NixOS Flake)
├── manifests/      # ③ アプリ層 (Kubernetes マニフェスト)
│   ├── common/     #   CNI (Cilium)
│   ├── bootstrap/  #   namespace・Argo CD
│   └── apps/       #   Argo CD が同期するアプリ群 (ApplicationSet)
├── playbooks/      # Ansible (データストア・Omada Controller など IaC 移行前のリソース)
├── scripts/        # ブートストラップ・適用スクリプト
├── docs/           # アーキテクチャ・運用ガイド・トラブルシューティング
├── truenas/        # TrueNAS の OpenTofu 構成
└── resources/      # PVE 関連の静的リソース
```

## セットアップ・運用

日常運用の手順(前提ツール、変更作業、コンポーネント別の運用、障害対応)は [docs/operations.md](./docs/operations.md) に記載

### クラスターのブートストラップ

```bash
# Talos VM の作成 → クラスターのブートストラップ → kubeconfig の取得までを一括実行する
./scripts/bootstrap-cluster.sh

# CNI・Argo CD・アプリの適用
./scripts/apply-apps.sh
```

詳細な手順は [docs/operations.md](./docs/operations.md) の「クラスターのブートストラップ」を参照。

### 日常の変更作業

- **インフラ変更**: `terraform/vpc/<zone>/` 配下を編集し `terragrunt apply`
- **NixOS ホスト変更**: `nix/hosts/<host>/` を編集。LXC は自動 Pull、VM は手動で `nixos-rebuild switch --flake`
- **アプリ変更**: `manifests/apps/` を編集して master に push すると Argo CD が自動同期する

## ドキュメント

| ドキュメント | 内容 |
| :-- | :-- |
| [docs/architecture.md](./docs/architecture.md) | 全体構成図・ネットワーク・K8s 構成・リソース一覧 |
| [docs/operations.md](./docs/operations.md) | 運用ガイド(セットアップ、日常作業、障害対応) |
| [docs/secrets-management.md](./docs/secrets-management.md) | SOPS + Age によるシークレット管理方針 |
| [docs/TROUBLESHOOTING.md](./docs/TROUBLESHOOTING.md) | トラブルシューティング |
| [docs/setup.md](./docs/setup.md) | セットアップ手順(物理ノード構築〜クラスター作成) |
| [docs/cloud.md](./docs/cloud.md) | マルチテナント環境の要件定義 |
| [docs/network_design.md](./docs/network_design.md) | ネットワーク詳細設計 (ASN / VNI / IPAM) |
