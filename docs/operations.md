# 運用ガイド (Operations Guide)

日常運用・変更作業・障害対応の手順をまとめる

## 1. 前提: ローカル環境のセットアップ

必要な CLI ツール: `terragrunt` (+ `tofu`), `talosctl`, `kubectl`, `kustomize`, `helm`, `sops`, `age`, `nix`

```bash
# Kubernetes / Talos への接続設定
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig
export TALOSCONFIG=terraform/vpc/zone-private-k8s/talosconfig
```

SOPS の復号には管理者の Age 鍵 (`~/.config/sops/age/keys.txt`) が必要

### 接続確認

```bash
kubectl get nodes
talosctl -e 192.168.5.200:50000 -n 10.20.1.11 services
```

## 2. 日常の変更作業

### 2.1 Kubernetes アプリの追加・変更 (GitOps)

Argo CD が master ブランチを監視しているため、**master へ push するだけで自動同期される** (prune + selfHeal 有効)。

- **本リポジトリ管理のアプリ**: `manifests/apps/<アプリ名>/overlays/prod` を作成すると ApplicationSet (`appset-prod.yaml`) が自動検出し、`<アプリ名>` namespace にデプロイする
- **外部リポジトリのアプリ**: `manifests/apps/multi-repo-deploy.yaml` の `elements` にリポジトリを追加する。対象リポジトリ側には `k8s/overlays/prod` が必要
- **シークレットを含むマニフェスト**: SOPS で暗号化してコミットする (argocd-vault-plugin が同期時に復号)

```bash
# 同期状態の確認
kubectl get apps -n argocd
# Argo CD UI (Ingress 経由)
open https://argocd.cluster.wpc
```

PostgreSQL primary の宛先 (`10.20.1.28`) は `manifests/apps/pg-cluster/base/service.yaml` 内の EndpointSlice で定義しており、Argo CD が同期する (Argo CD の `resource.exclusions` から EndpointSlice を除外対象外にすることで管理可能にしている)。

### 2.2 NixOS ホストの変更 (lb-1/2/3, egress-gateway など)

LXC ホストには `system.autoUpgrade` が設定されており、**master へ push すれば起動時 (30 秒後) および daily で自動適用される**。

即時反映したい場合:

```bash
# リモートから手動適用
nixos-rebuild switch --flake ./nix#lb-1 --target-host nixos@192.168.5.201 --use-remote-sudo

# もしくはコンテナ内で自動アップグレードをトリガー
sudo systemctl start nixos-upgrade.service
journalctl -u nixos-upgrade.service -f
```

VM ホスト (dev-server, lm-server) は手動 Push 型:

```bash
# TODO: VM ホストの運用自動化
nixos-rebuild switch --flake ./nix#lm-server --target-host nixos@192.168.5.222 --use-remote-sudo
```

`nix/` 配下の変更を master に push すると、GitHub Actions (`nix-images.yaml`) が LXC ベースイメージをビルドして GitHub Release (`nix-images-lxc`) に公開する

### 2.3 インフラ (Proxmox / SDN / VM / LXC) の変更

Terragrunt を対象ゾーンのディレクトリで実行する (Push 型・手動)。

```bash
# 例: k8s ゾーンの変更
terragrunt --terragrunt-working-dir terraform/vpc/zone-private-k8s plan
terragrunt --terragrunt-working-dir terraform/vpc/zone-private-k8s apply
```

| ディレクトリ | 管理対象 |
| :-- | :-- |
| `terraform/pve/hosts` | 物理ノードのブリッジ・VLAN・SDN Fabric (OSPF) |
| `terraform/pve/vm` | 旧セグメントの VM (oc1-nfs, oc1-omada) |
| `terraform/pve/server-2` | server-2 上の lm-server (非常時稼働・import 保存のみ) |
| `terraform/vpc/cloudflare` | Cloudflare Tunnel・Zero Trust ポリシー |
| `terraform/vpc/zone-dev` | dev-server VM |
| `terraform/vpc/zone-private` | EVPN zone: private + prvmain VNet |
| `terraform/vpc/zone-private-k8s` | Talos クラスター・lb-1/2/3・egress-gateway |
| `terraform/vpc/zone-private-persistent` | PostgreSQL LXC (pg-1/2/3) |
| `terraform/vpc/zone-xxx` | その他 SND Zone |
| `truenas/` | TrueNAS の設定 (Terragrunt 管理外・単体の tofu 構成) |

注意点:

- state はローカル (`terraform.tfstate`) 管理。実行マシンを固定し、state ファイルの扱いに注意する
- 認証情報は `terraform/secrets.yaml` (SOPS 管理) から `root_sops.hcl` 経由で復号・読み込みされる。旧 `secrets.hcl` (`root.hcl`) は廃止済みで、参照するとエラーになる
- **BGP EVPN Controller は Terraform 管理外**であり、GUI (Datacenter > SDN > Controllers) で手動作成する
- `oc1-nfs` は `protection = true` のため誤削除は防止されるが、データ本体のバックアップは別途必要

### 2.4 シークレットの変更

```bash
# 編集 (自動で復号 → エディタ → 再暗号化)
sops terraform/secrets.yaml
sops truenas/secrets.yaml
sops nix/hosts/<host>/secrets.yaml

# 新しい受信者 (Age 公開鍵) を追加した場合は .sops.yaml を編集して再暗号化
sops updatekeys <file>
```

Kubernetes 用のシークレットは、SOPS 暗号化したマニフェストをデプロイ対象リポジトリ側にコミットする (Argo CD の AVP プラグインが同期時に復号)。

鍵の管理区分・ローテーション手順は [secrets-management.md](./secrets-management.md) を参照。

## 3. クラスターのブートストラップ (再構築)

Talos クラスターをゼロから構築する手順。

```bash
# 1. SDN ゾーンが存在することを確認 (なければ先に apply)
terragrunt --terragrunt-working-dir terraform/vpc/zone-private apply

# 2. クラスター構築 (terragrunt apply → Talos bootstrap → kubeconfig 取得まで自動)
bash scripts/bootstrap-cluster.sh

# 3. CNI (Cilium)・Argo CD・シークレット・アプリの適用
#    事前に ~/.config/sops/age/argocd_key.txt (Argo CD 用 Age 鍵) が必要
bash scripts/apply-apps.sh
```

以降のアプリ管理はすべて Argo CD に委譲される。

## 4. コンポーネント別の運用

TODO: 

## 5. 障害対応チェックリスト

### アプリにアクセスできない (`*.cluster.wpc` が開けない)

1. DNS: `dig @192.168.5.200 argocd.cluster.wpc` → 応答がなければ lb の CoreDNS / VIP を確認
2. VIP: keepalived がどの lb にいるか確認 (上記 4.1)。全滅していれば lb LXC を Proxmox から再起動
3. HAProxy → NodePort: `curl -vk https://192.168.5.200` で 応答を確認。worker ノードの NodePort (30443) が生きているか
4. k8s 内: `kubectl get pods -A | grep -v Running`、`kubectl get applications -n argocd` で Degraded を確認

### kubectl が繋がらない

1. `KUBECONFIG` が設定されているか (`connection refused (localhost:8080)` は未設定のサイン)
2. lb の 6443 が通るか: `nc -vz 192.168.5.200 6443` (許可ソースは `192.168.5.0/24` のみ)
3. CP ノードの状態: `talosctl -e 192.168.5.200:50000 -n 10.20.1.11 etcd status`

### Argo CD が Sync しない / Secret が壊れる

1. `kubectl describe application <app> -n argocd` でエラー内容を確認
2. SOPS 復号エラーの場合、`sops-age-key` Secret (argocd namespace) が存在するか確認。消えていれば `apply-apps.sh` 内の手順で再登録
3. repo-server の AVP プラグインログ: `kubectl logs -n argocd deploy/argocd-repo-server -c avp`

### NixOS LXC が設定を反映しない

1. `journalctl -u nixos-upgrade.service` で autoUpgrade の失敗理由を確認 (flake 評価エラー・ネットワーク不通が多い)
2. sops-nix の復号失敗の場合、`/var/lib/sops-nix/key.txt` が存在するか確認 (Terraform が LXC 作成時に注入する)

### Proxmox ノード障害

- 全ロール (CP / worker / lb / pg) が 3 ノードに分散配置されているため、1 ノード停止では quorum (etcd / PVE cluster) は維持される
- 復旧後、Talos ノードは自動で再参加する。keepalived は nopreempt のため VIP は移動したまま
- ノードの入れ替え手順は [replace-all-node.md](./replace-all-node.md) を参照

### その他の既知の問題

[TROUBLESHOOTING.md](./TROUBLESHOOTING.md) を参照 (GPU パススルー、multipass 等)。

## 6. 定期・随時のメンテナンスタスク

| タスク | 頻度 | 方法 |
| :-- | :-- | :-- |
| NixOS flake input の更新 | 随時 | `nix flake update nix-config --flake ./nix` → push (autoUpgrade で反映) |
| Talos / Kubernetes バージョンアップ | 随時 | `modules/k8s-cluster/talos.tf` のバージョンを更新して apply。CP → worker の順にローリング |
| Cilium 等 Helm チャート更新 | 随時 | `manifests/common/cilium/kustomization.yaml` の version を更新 |
| Terraform provider 更新 | 随時 | `terraform/root_sops.hcl` の version を更新 |
| terraform.tfstate のバックアップ | 変更時 | ローカル state のため、実行マシンのバックアップに含める |
| Age マスターキーのバックアップ確認 | 年 1 回程度 | 1Password 等に `~/.config/sops/age/keys.txt` があるか確認 |

## 7. 既知の技術的負債・注意点

- **`scripts/apply-datastore.sh` は旧構成向け**: 参照先の `terraform/environments/dev-persistent` や `playbooks/postgres.yml` は現存しない
- **`playbooks/` が古い**: 過去に構築した NFS 等は Terragrunt + NixOS 構成に未移行
- **Terraform state がローカル**: リモートバックエンド未導入のため、実行マシンの喪失 = state の喪失となる
- **EVPN Controller / zfs 等は手動設定**: [setup.md](./setup.md) 参照
- **監視・バックアップは整備途上** (README の TODO): nuage-monitoring-stack は Argo CD 管理だが、PBS 等のバックアップ基盤は未構築
