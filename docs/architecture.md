# アーキテクチャ

## 1. 物理構成

Proxmox VE の物理 3 ノード (nuc-1 / nuc-2 / server-1) と通常時は非稼働の server-2 で構成する。各ノードは役割ごとに 3 系統の NIC を持ち、それぞれ別の L2 セグメントに接続する。

- **vmbr0 — VLAN (192.168.5.0/24)**: Proxmox 管理 (GUI/SSH) と SDN の出口 (SNAT)。上流は「Internet → ONU/メインルーター (192.168.1.0/24) → Omada VLAN ルーター ER605 (192.168.1.201) → Omada L2 スイッチ ES200GMP」
- **vmbr10 — SDN Fabric (10.0.0.0/24)**: EVPN/VXLAN アンダーレイ専用。専用の L2 スイッチに収容し、VLAN 1/2/3 のサブインターフェースでノード間の論理 P2P リンクを構成する。nuc-1/nuc-2 は USB NIC を使用
- **vmbr11 — 予備 (10.0.1.0/24)**: 未使用の予備セグメント
- server-1 のみ `vmbr1` (192.168.1.0/24 接続) を追加で持ち、Proxy 用に使用する
- server-2 は普段は電源オフで、必要に応じて稼働する (lm-server をホスト)

<img src="./architecture-physical.drawio.svg" style="background-color: #121212; padding: 8px;">

## 2. SDN 構成 (アンダーレイ / EVPN)

物理構成のうち `vmbr10` (SDN Fabric) 上にアンダーレイとオーバーレイを構成する。

- **SDN Fabric**: `vmbr10` 上の VLAN サブインターフェースでノード間をリング接続し、OSPF (fabric `main`, `10.254.1.0/24`, area 1) でアンダーレイの経路交換を行う
- **EVPN Controller**: BGP EVPN コントローラーは GUI で手動作成する(Terraform 管理外)
- **オーバーレイ**: EVPN ゾーンごとに VRF を分離し、VNet (VXLAN) を払い出す。全ノードが Exit Node であり、SNAT で `vmbr0` からインターネットへ抜ける
- **ゾーン**: 個人用 Kubernetes 等は zone: private に構築。テナントや用途が増えたら、同じ仕組みで EVPN ゾーンを追加して払い出せる

<img src="./architecture-network.drawio.svg" style="background-color: #121212; padding: 8px;">

## 3. Kubernetes クラスター構成 (zone: private)

Talos Linux の 6 ノードクラスターを `prvmain` VNet (10.20.1.0/24) 上に構築している。CNI は Cilium (kube-proxy 置換) であり、Ingress も Cilium の IngressClass を使用する。

<img src="./architecture-k8s.drawio.svg" style="background-color: #121212; padding: 8px;">

ポイント:

- **API アクセス**: `kubectl` / `talosctl` は HAProxy の外部 VIP `192.168.5.200` (6443 / 50000) 経由でアクセスする。ソース `192.168.5.0/24` のみ許可
- **DNS**: lb 上の CoreDNS が `*.cluster.wpc` / `*.nuage.cluster.wpc` を `192.168.5.200` に解決する。それ以外は `8.8.8.8` へフォワード
- **PostgreSQL**: クラスター外の LXC (pg-1/2/3) で稼働し、k8s からは `pg-cluster` namespace の Service + EndpointSlice (`10.20.1.28`) 経由で参照する。
- **NFS**: nfs-proxy (HAProxy TCP 2049) が旧セグメントの `oc1-nfs` VM に中継する
- **動的ボリューム**: local-path-provisioner (`/var/local-path-provisioner` への hostPath) により PVC の動的プロビジョニングを提供する

## 4. IaC・GitOps 運用ワークフロー

管理レイヤーは 3 つあり、いずれも本リポジトリを起点とする。

<img src="./architecture-workflow.drawio.svg" style="background-color: #121212; padding: 8px;">

### 各層の役割

| 層 | ツール | 対象 | 適用方法 |
| :-- | :-- | :-- | :-- |
| ① インフラ | Terragrunt + OpenTofu/Terraform (bpg/proxmox, siderolabs/talos, cloudflare) | SDN・VM・LXC・Talos マシン設定・Cloudflare Tunnel | ローカルから `terragrunt apply` (手動 Push 型) |
| ② OS | Nix Flake + nixos-generators + sops-nix | NixOS LXC (lb-*, nfs-proxy) / VM (dev-server, lm-server) | LXC は `system.autoUpgrade` による自動 Pull。VM は `nixos-rebuild switch --flake` で手動 Push |
| ③ アプリ | Argo CD (ApplicationSet + Kustomize + argocd-vault-plugin/SOPS) | Kubernetes 上の全アプリ | master ブランチへの push で自動同期 |

### Argo CD の Application 検出規則

- `appset-prod.yaml`: 本リポジトリの `manifests/apps/*/overlays/prod` ディレクトリを自動検出し、`<アプリ名>` namespace にデプロイする
- `multi-repo-deploy.yaml`: 外部リポジトリ (`bare-web-proxy`, `nuage-monitoring-stack`, `pechka`) の `k8s/overlays/prod` を SOPS プラグイン付きでデプロイする

### シークレット管理

SOPS + Age による暗号化で全シークレットを Git 管理する。マスターキーは管理者ローカルの Age 鍵 1 つのみ。詳細は [secrets-management.md](./secrets-management.md) を参照。

## 5. リソース一覧 (IP / VMID)

### 物理ノード

| ノード | 管理 IP (vmbr0) | SDN Fabric (vmbr10) | 予備 (vmbr11) | 備考 |
| :-- | :-- | :-- | :-- | :-- |
| nuc-1 | 192.168.5.21 | 10.0.0.10 (fabric: 10.254.1.21) | 10.0.1.10 | |
| nuc-2 | 192.168.5.22 | 10.0.0.11 (fabric: 10.254.1.22) | 10.0.1.11 | |
| server-1 | 192.168.5.25 | 10.0.0.12 (fabric: 10.254.1.25) | 10.0.1.12 | vmbr1 / vmbr10 (PVE on PVE 用) あり |
| server-2 | 192.168.5.26 | - | - | 必要に応じて稼働。lm-server (Ollama) をホスト |

### VM / LXC (zone: private = prvmain 10.20.1.0/24)

| 名前 | VMID | 配置 | prvmain IP | LAN IP (vmbr0) | 役割 |
| :-- | :-- | :-- | :-- | :-- | :-- |
| controlplane-01/02/03 | 201-203 | nuc-1 / nuc-2 / server-1 | 10.20.1.11-13 | - | Talos CP (VIP: 10.20.1.10) |
| worker-01/02/03 | 206-208 | nuc-1 / nuc-2 / server-1 | 10.20.1.16-18 | - | Talos Worker |
| lb-1/2/3 | 211-213 | nuc-1 / nuc-2 / server-1 | 10.20.1.21-23 | 192.168.5.201-203 | HAProxy + keepalived + CoreDNS (VIP: 10.20.1.20 / 192.168.5.200) |
| pg-1/2/3 | 215-217 | nuc-1 / nuc-2 / server-1 | 10.20.1.25-27 | 192.168.5.205-207 | PostgreSQL (primary Endpoint: 10.20.1.28) |
| nfs-proxy | 220 | server-1 | 10.20.1.30 | 192.168.5.220 | NFS 中継 (→ 192.168.5.151:2049) |

### その他 VM

| 名前 | VMID | 配置 | IP | 役割 |
| :-- | :-- | :-- | :-- | :-- |
| oc1-nfs | 1151 | server-1 | 192.168.5.151 | NFS サーバー (1TB, protection 有効) |
| dev-server | 1152 | server-1 | 192.168.5.199 | NixOS 開発サーバー (16c/32GB) |
| oc1-omada | 1163 | server-1 | - | Omada Controller |
| lm-server | 200 | server-2 | 192.168.5.222 | Ollama (ROCm) |

このほか、追加で払い出した EVPN ゾーン上にも VM を配置できる(上記一覧は zone: private と管理系のみを記載)。
