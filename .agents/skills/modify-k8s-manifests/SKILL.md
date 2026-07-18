---
name: modify-k8s-manifests
description: Reference of conventions, commands, and validation techniques for changing Kubernetes manifests managed by Argo CD (manifests/, ApplicationSet, kustomize, Talos).
---

# Kubernetes 資材の変更

`manifests/` 配下および Argo CD 管理のアプリを変更する際に使う手段のカタログ。障害調査は [[troubleshoot-k8s-app]] を参照。

## 構成と規約

- `manifests/bootstrap/`: namespace・Argo CD 本体 (クラスタ構築時に `scripts/apply-apps.sh` で適用)
- `manifests/common/`: Cilium 等の基盤コンポーネント
- `manifests/apps/<app>/overlays/prod`: 本リポジトリ管理アプリ。作成すると ApplicationSet (`appset-prod.yaml`) が自動検出し、`<app>` namespace にデプロイする
- `manifests/apps/multi-repo-deploy.yaml`: 外部リポジトリのアプリ一覧。対象リポジトリ側に `k8s/overlays/prod` が必要。AVP プラグイン (sops モード) 経由で同期される
- master へ push するだけで Argo CD が自動同期する (prune + selfHeal 有効、ServerSideApply)
- k8s から PostgreSQL primary への宛先 IP は `manifests/apps/pg-cluster/base/service.yaml` の EndpointSlice (`primary` Service) で定義

## ローカル検証

```bash
export PATH=$HOME/.nix-profile/bin:$PATH

# レンダリング確認
kustomize build manifests/apps/<app>/overlays/prod

# 全マニフェストの build + kube-linter 検証 (.kube-linter.yaml 準拠)
bash scripts/validate-manifests.sh
```

## 同期状態の確認

```bash
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

kubectl get applications -n argocd
kubectl describe application <app> -n argocd
# Argo CD UI
open https://argocd.cluster.wpc
```

## 一時デプロイでの検証

Argo CD を待たずに検証したい場合、レンダリング結果を直接 apply できる:

```bash
kubectl apply -k manifests/apps/<app>/overlays/prod
```

- selfHeal + prune が有効なため、手動 apply した内容は Argo CD にいずれ巻き戻される。これを利用して「一時適用 → 検証 → ソース確定 → push」とする。手動変更を恒久対応にしない
- git 操作は行わず、ユーザーに依頼すること
- シークレットを含むマニフェストは AVP が同期時に復号するため、手動 apply では復号されない点に注意 ([[sops-secrets]])

## Talos ノードの操作

```bash
export TALOSCONFIG=terraform/vpc/zone-private-k8s/talosconfig

talosctl -e 192.168.5.200:50000 -n 10.20.1.11 services
talosctl -e 192.168.5.200:50000 -n 10.20.1.11 etcd status
```

- Talos / Kubernetes のバージョンは `terraform/vpc/modules/k8s-cluster/talos.tf` で管理。CP → worker の順にローリング
- Cilium のバージョンは `manifests/common/cilium/kustomization.yaml` で管理

## 注意点・既知の罠

- Argo CD の `resource.exclusions` は EndpointSlice を除外対象外にしてある (pg-cluster の VIP 管理のため)。同種の設定変更時は影響を確認する
- 外部リポジトリアプリのマニフェスト変更は、このリポジトリではなく対象リポジトリ (`../pechka` 等) 側の `k8s/` を変更する
- イメージ更新の自動化には keel (`manifests/apps/keel`) が動いている
