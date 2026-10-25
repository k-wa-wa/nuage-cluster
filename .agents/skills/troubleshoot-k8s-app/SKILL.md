---
name: troubleshoot-k8s-app
description: Reference of investigation techniques for apps running on the cluster - locating the source repo, tracing the network path, reading logs across k8s / Argo CD / NixOS layers.
---

# クラスタ上のアプリの障害調査

`*.cluster.wpc` のアプリや k8s 上のワークロードに問題が起きたときに使う調査手段のカタログ。

## ソースコードの特定

- 本リポジトリ管理アプリ: `manifests/apps/<app>/`
- 外部リポジトリアプリ: `manifests/apps/multi-repo-deploy.yaml` の `elements` を見る (pechka, nuage-monitoring-stack, bare-web-proxy 等)。ローカルには兄弟ディレクトリ (`../pechka` 等) として checkout されていることが多い。マニフェストは対象リポジトリの `k8s/overlays/prod`
- ミドルウェア (PostgreSQL, MinIO 等) は k8s 外の NixOS LXC。定義は `nix/hosts/<name>/` ([[modify-nix-host]])

## k8s 層の調査コマンド

```bash
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

kubectl get pods -A | grep -v Running
kubectl get applications -n argocd            # Degraded / OutOfSync の確認
kubectl describe application <app> -n argocd
kubectl -n <ns> logs <pod> [-c <container>] [--previous]
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> get events --sort-by=.lastTimestamp
kubectl -n argocd logs deploy/argocd-repo-server -c avp   # SOPS/AVP 復号エラー
```

## 経路の切り分け (`*.cluster.wpc` が開けない)

DNS → VIP → HAProxy → NodePort → Pod の順に切り分ける:

```bash
dig @192.168.5.200 argocd.cluster.wpc     # lb の CoreDNS
ssh lb-1 "ip a | grep 192.168.5.200"      # keepalived VIP がどの lb にいるか
curl -vk https://192.168.5.200            # HAProxy → NodePort (30443)
```

lb (HAProxy / CoreDNS / keepalived) の実体は NixOS LXC (`nix/hosts/loadbalancer`)。`ssh lb-1` でログを確認できる。

## NixOS ミドルウェア層の調査

```bash
ssh pg-cluster-1 "systemctl status patroni"
ssh <host> "journalctl -u <service> -n 50 --no-pager"
```

- PostgreSQL の VIP (`10.20.1.40`) は keepalived (`nix/hosts/postgres-cluster/keepalived.nix`) が管理。k8s からの宛先 IP は EndpointSlice (`manifests/apps/pg-cluster/base/service.yaml`) で定義しており、両者は別管理のためズレていないか確認する
- DB のユーザー・データベース作成は `nix/hosts/postgres-cluster/patroni.nix` の `bootstrap.post_init` で行われる

## 修正の適用手段

- **ソース修正が本対応**。k8s マニフェストなら [[modify-k8s-manifests]]、NixOS なら [[modify-nix-host]]、インフラなら [[modify-terraform]] の手段で直す
- 検証目的の一時適用手段:
  - `kubectl apply -k <overlay>` / `kubectl rollout restart deploy/<name>` (selfHeal で巻き戻る)
  - NixOS は rsync + `/tmp/nix` からの一時 rebuild ([[modify-nix-host]])
- 障害対応チェックリストは `docs/operations.md` §5 も参照
