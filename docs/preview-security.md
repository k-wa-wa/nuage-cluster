# プレビュー環境のセキュリティ設計と多層防御

## 1. 概要

公開リポジトリ（`pechka`, `bare-web-proxy`, `nuage-monitoring-stack`）に対する PR を検知して自動デプロイする Argo CD の Preview ApplicationSet において、クラスタ内 RCE（特権昇格・ホスト脱獄・本番 DB 認証情報奪取等）を防止するためのセキュリティ構成である。

信頼された開発者（`k-wa-wa` および `bot-wa-wa`）の PR に対しては完全自動デプロイを維持しつつ、外部からの不正デプロイ遮断と、悪意あるマニフェストに対するクラスタ・ノード保護を多層防御で実現する。

## 2. 多層防御アーキテクチャ

1. **入口防御 (GitHub Actions ラベル制御 & ApplicationSet フィルタ)**:
   - ApplicationSet の PullRequest generator で `labels: ["preview"]` を必須とする。
   - `preview` ラベルがない PR は Argo CD の検知対象外となり、デプロイされない。
   - アプリケーションリポジトリ側で `auto-preview-label.yml` を動かし、信頼された開発者（`k-wa-wa`, `bot-wa-wa`）の PR のみ自動でラベルを付与する。外部ユーザーの PR や、外部ユーザーがコミットを追加した PR からはラベルを剥奪する。
2. **Argo CD レイヤー防御 (AppProject `preview-apps`)**:
   - `preview-apps` AppProject を新設し、すべての preview ApplicationSet を所属させる。
   - `destinations`: 各 PR 専用 Namespace（`pechka-pr-*`, `bare-web-proxy-pr-*`, `nuage-monitoring-stack-pr-*`）のみに限定し、prod や kube-system へのデプロイを遮断する。
   - `clusterResourceWhitelist`: `[{group: '', kind: Namespace}]` のみ許可する。ClusterRole, ClusterRoleBinding, CRD, PersistentVolume 等のクラスタスコープリソースの作成を一切禁止する。
   - `namespaceResourceWhitelist`: preview overlay で実際に使用される Namespace スコープリソースのみをホワイトリスト化する。
3. **ノード・ホスト保護 (Pod Security Admission `baseline`)**:
   - ApplicationSet の Kustomize patches で、Preview Namespace に対し Pod Security Standards の `baseline` 基準を強制する。
   - `pod-security.kubernetes.io/enforce: baseline`
   - 特権コンテナ (`privileged: true`)、ホストネットワーク (`hostNetwork: true`)、ホストパス (`hostPath`) 等の利用を拒否し、ノード脱獄を防止する。

## 3. アプリケーションリポジトリ側 GitHub Actions 設定

各アプリケーションリポジトリ（`pechka`, `bare-web-proxy`, `nuage-monitoring-stack`）の `.github/workflows/auto-preview-label.yml` に以下を配置する。

```yaml
name: Auto Preview Label

on:
  pull_request_target:
    types: [opened, synchronize, reopened]

permissions:
  pull-requests: write

jobs:
  manage-preview-label:
    runs-on: ubuntu-latest
    steps:
      - name: Manage preview label based on actor trust
        uses: actions/github-script@v7
        with:
          script: |
            const trustedUsers = ['k-wa-wa', 'bot-wa-wa'];
            const prAuthor = context.payload.pull_request.user.login;
            const eventActor = context.actor;

            const isAuthorTrusted = trustedUsers.includes(prAuthor);
            const isActorTrusted = trustedUsers.includes(eventActor);

            const { owner, repo } = context.repo;
            const issue_number = context.payload.pull_request.number;

            const currentLabels = context.payload.pull_request.labels.map(l => l.name);
            const hasPreviewLabel = currentLabels.includes('preview');

            if (isAuthorTrusted && isActorTrusted) {
              if (!hasPreviewLabel) {
                console.log(`Adding preview label (Author: ${prAuthor}, Actor: ${eventActor})`);
                await github.rest.issues.addLabels({
                  owner,
                  repo,
                  issue_number,
                  labels: ['preview'],
                });
              } else {
                console.log('Preview label already present.');
              }
            } else {
              if (hasPreviewLabel) {
                console.log(`Removing preview label due to untrusted activity (Author: ${prAuthor}, Actor: ${eventActor})`);
                await github.rest.issues.removeLabel({
                  owner,
                  repo,
                  issue_number,
                  name: 'preview',
                });
              } else {
                console.log(`Untrusted PR activity (Author: ${prAuthor}, Actor: ${eventActor}). Preview label not added.`);
              }
            }
```

### 留意事項
- `pull_request_target` を使用することで、fork からの PR や第三者のコミットに対しても、リポジトリ本体の信頼されたコードと権限で安全にラベル制御を実行できる。
- ワークフロー内で untrusted な PR コードを checkout しないこと。

## 4. 移行手順

本変更をマージすると、`preview` ラベルを持たない既存の open PR に対応する preview Application は ApplicationSet の generator から即座に外れる。Application に設定された `resources-finalizer` により、プレビュー環境の Namespace や PVC が自動削除される。

既存のプレビュー環境を停止させずに安全に移行するため、以下の順序で適用を行う：

1. **アプリリポジトリ側への先行導入**:
   - `pechka`, `bare-web-proxy`, `nuage-monitoring-stack` に `auto-preview-label.yml` をマージして導入する。
2. **既存 open PR への手動ラベリング**:
   - 稼働を継続したい既存の open PR に対し、GitHub 上で手動で `preview` ラベルを付与する。
3. **nuage-cluster の本 PR マージ**:
   - nuage-cluster の master へ本変更をマージする。Argo CD の root app により `preview-apps` AppProject と各 ApplicationSet が自動同期される。

## 5. マージ後のクラスタ確認手順

マージ後、クラスタ管理者または開発者は以下のコマンドで AppProject および Application の同期状態を確認する。

```bash
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

# 1. preview-apps AppProject の作成とホワイトリストの確認
kubectl get appproject preview-apps -n argocd -o yaml

# 2. preview Application の一覧と同期状態の確認
kubectl get applications -n argocd -l argocd.argoproj.io/project=preview-apps

# 3. 許可外リソースや拒否エラーの有無を確認
kubectl describe applications -n argocd -l argocd.argoproj.io/project=preview-apps | grep -E "Status:|Message:"
```

## 6. 残存リスクと設計上の制限事項

多層防御を導入しても、Argo CD および Kubernetes の設計仕様上、以下の残存リスクが存在する：

1. **Namespace の名前制限（クラスタスコープリソース）**:
   - Argo CD の `spec.destinations` は Namespace スコープリソースを対象とするため、クラスタスコープである `kind: Namespace` 自体の名前（`metadata.name`）は destinations による prefix 制限（`pechka-pr-*` 等）を受けない。
   - 悪意ある PR がマニフェスト内で `metadata.name: pechka` 等の本番 Namespace を指定した場合、Server-Side Apply による設定競合や、PR クローズ時の prune により本番 Namespace が影響を受けるリスクが理論上残る。そのため、外部 PR に対する不用意なラベリングは避け、マニフェストの差分レビューを継続する。
2. **入口ラベル制御の TOCTOU / 遅延時のフェイルオープン**:
   - 第三者が悪意あるコミットを push してから GitHub Actions が起動して `preview` ラベルを剥奪するまでの間にわずかな時間差（窓）が存在する。この間に ApplicationSet のポーリング（`requeueAfterSeconds: 180`）が走った場合、悪意あるコミットの SHA でデプロイが試行される可能性がある。
   - GitHub Actions の障害や遅延、API エラー発生時、ラベルは剥奪されず維持される（fail-open）。
3. **ラベル自動再付与の振る舞い**:
   - 第三者がコミットを追加してラベルが剥奪された後、信頼された開発者（`k-wa-wa`）がその PR に対して push した場合、`auto-preview-label.yml` は再度 `preview` ラベルを自動付与する。第三者のコミットが残った状態で push すると第三者のコードがデプロイされるため、外部からのコミットが混入している PR を引き継ぐ際は、必ずコミット内容を精査した上で作業を行う。
