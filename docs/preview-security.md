# プレビュー環境のセキュリティ設計と多層防御

## 1. 概要

公開リポジトリ（`pechka`, `bare-web-proxy`, `nuage-monitoring-stack`）に対する PR を検知して自動デプロイする Argo CD の Preview ApplicationSet において、クラスタ内 RCE（特権昇格・ホスト脱獄・本番 DB 認証情報奪取等）を防止するためのセキュリティ構成である。

信頼された開発者（`k-wa-wa` および `bot-wa-wa`）の PR に対しては完全自動デプロイを維持しつつ、外部からの不正デプロイ遮断と、万が一の悪意あるマニフェストに対するクラスタ・ノード保護を多層防御で実現する。

## 2. 多層防御アーキテクチャ

1. **入口防御 (GitHub Actions ラベル制御 & ApplicationSet フィルタ)**:
   - ApplicationSet の PullRequest generator で `labels: ["preview"]` を必須とする。
   - `preview` ラベルがない PR は Argo CD の検知対象外となり、デプロイされない。
   - アプリケーションリポジトリ側で `auto-preview-label.yml` を動かし、信頼された開発者（`k-wa-wa`, `bot-wa-wa`）の PR のみ自動でラベルを付与する。外部ユーザーの PR や、外部ユーザーがコミットを追加した PR からは即座にラベルを剥奪する。
2. **Argo CD レイヤー防御 (AppProject `preview-apps`)**:
   - `preview-apps` AppProject を新設し、すべての preview ApplicationSet を所属させる。
   - `destinations`: 各 PR 専用 Namespace（`pechka-pr-*`, `bare-web-proxy-pr-*`, `nuage-monitoring-stack-pr-*`）のみに限定し、prod や kube-system へのデプロイを遮断する。
   - `clusterResourceWhitelist`: `[]`（空配列）とし、ClusterRole, ClusterRoleBinding, CRD, PersistentVolume 等のクラスタスコープリソースの作成を一切禁止する。
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
