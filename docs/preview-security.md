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
4. **CI ビルド・本番シークレット隔離 (Layer 4)**:
   - PR イメージのビルド・push は信頼されたトリガーに制限し、本番用シークレットとプレビュー用リソースを分離する。
5. **ネットワーク隔離ガードレールと恒常的検証 (Layer 5: `CiliumClusterwideNetworkPolicy` & `CronJob`)**:
   - クラスタ全体のガードレールとして `CiliumClusterwideNetworkPolicy` (`preview-isolation-guardrail`) を配置し、`pod-security.kubernetes.io/enforce: baseline` ラベルが付与されたすべての Preview Namespace の Pod を自動捕捉する。
   - 自宅 LAN（`192.168.0.0/16`：Proxmox, PBS, ルータ等）、クラスタ内部ゾーン（`10.0.0.0/8`：k8s ノード, Talos API, etcd 等）、プライベート・CGNAT・リンクローカル帯、および本番・システム Namespace（`argocd`, `pechka` 本番, `kube-system` 等）への通信（横展開）を全面遮断する。
   - プレビュー環境内の Pod 間通信、Ingress Controller からの流入、CoreDNS（`53/UDP`, `53/TCP`）による名前解決、パブリックインターネット通信、および `pechka` プレビューが参照する本番外部リソース（MinIO `10.20.1.60:9000/TCP`、初期シード用 PostgreSQL `10.20.1.40:5432/TCP`）のみをピンポイントで許可する。
   - プレビュー環境と同一の PSA ラベルを持つ検証用 Namespace (`preview-isolation-test`) 上で 15 分おきに検証用 `CronJob` を実行し、ポリシーの適用漏れや構成ドリフトを継続的に自動検知する。

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

## 5. ネットワーク隔離ガードレール (Layer 5) と恒常的検証 CronJob の設計・運用

### 5.1 `CiliumClusterwideNetworkPolicy` (`manifests/apps/preview-network-policy.yaml`)

アプリリポジトリ側のマニフェスト改変によって回避されないよう、`nuage-cluster` 側のクラスタスコープリソース（`CiliumClusterwideNetworkPolicy`: `preview-isolation-guardrail`）として強制する。

- **捕捉条件 (`endpointSelector`)**:
  - `io.cilium.k8s.namespace.labels.pod-security.kubernetes.io/enforce: baseline`
  - ApplicationSet のパッチで付与される PSA `baseline` ラベルをセレクタとすることで、新規 PR ごとに動的に生成される Preview Namespace を漏れなく自動捕捉する。
- **Ingress 制御**:
  - プレビュー環境（`baseline` ラベル付き Namespace）内の Pod 間通信を許可。
  - Cilium Ingress (`fromEntities: [ingress]`) からの HTTP/HTTPS トラフィック流入を許可。
- **Egress 制御**:
  - プレビュー環境（`baseline` ラベル付き Namespace）内の Pod 間通信を許可。なお、`CiliumClusterwideNetworkPolicy` はクラスタスコープであるため、空の `matchLabels: {}` を指定するとクラスタ内の全 Namespace（`argocd` や本番 Namespace を含む）への通信が許可されてしまう。これを防ぐため、`toEndpoints` / `fromEndpoints` にも `io.cilium.k8s.namespace.labels.pod-security.kubernetes.io/enforce: baseline` を指定し、本番・システム Namespace への横展開を遮断する。
  - `kube-system` Namespace の CoreDNS (`k8s-app: kube-dns`) に対する `53/UDP` および `53/TCP` のみ許可。
  - `toCIDRSet` により `0.0.0.0/0` からプライベート IP 帯（`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, `100.64.0.0/10`, `169.254.0.0/16`）を除外し、パブリックインターネットへの通信のみを許可。
  - `pechka` プレビュー環境が必要とする本番 MinIO（SeaweedFS S3 VIP: `10.20.1.60/32` Port `9000/TCP`）および初期シード用本番 PostgreSQL（VIP: `10.20.1.40/32` Port `5432/TCP`）への Egress のみピンポイントで許可。

### 5.2 恒常的セキュリティ検証 CronJob (`manifests/apps/preview-isolation-test.yaml`)

ネットワークポリシーの適用漏れや Cilium 設定変更時の構成ドリフトを継続的に検知するため、`preview-isolation-test` Namespace に `CronJob` (`preview-isolation-test`) を常設する。

- **スケジュール**: 15 分おき（`*/15 * * * *`、`concurrencyPolicy: Forbid`）
- **検証項目 (`run-isolation-test.sh`)**:
  1. **遮断テスト（自宅 LAN / PBS `192.168.5.30:8007`）**: 接続がタイムアウトまたは拒否されれば PASS、疎通すれば FAIL。
  2. **遮断テスト（k8s コントロールプレーン / Talos API `10.20.1.11:50000`）**: 接続がタイムアウトまたは拒否されれば PASS、疎通すれば FAIL。
  3. **許可テスト（CoreDNS `10.96.0.10:53`）**: 疎通すれば PASS、遮断されれば FAIL。
  4. **許可テスト（パブリックインターネット `1.1.1.1:443`）**: 疎通すれば PASS、遮断されれば FAIL。
  5. **許可テスト（`pechka` 本番 MinIO VIP `10.20.1.60:9000`）**: 疎通すれば PASS、遮断されれば FAIL。
- 1 つでも違反があればスクリプトは Exit 1 で終了し、Job が `Failed` 状態として記録される（直近 3 件の失敗履歴を保持）。

## 6. マージ後のクラスタ確認・監視手順

マージ後、クラスタ管理者または開発者は以下のコマンドで AppProject、Application、ネットワーク隔離ポリシー、および検証 CronJob の状態を確認する。

```bash
export PATH=$HOME/.nix-profile/bin:$PATH
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

# 1. preview-apps AppProject の作成とホワイトリストの確認
kubectl get appproject preview-apps -n argocd -o yaml

# 2. preview Application の一覧と同期状態の確認
kubectl get applications -n argocd -l argocd.argoproj.io/project=preview-apps

# 3. 許可外リソースや拒否エラーの有無を確認
kubectl describe applications -n argocd -l argocd.argoproj.io/project=preview-apps | grep -E "Status:|Message:"

# 4. CiliumClusterwideNetworkPolicy の同期・適用状態の確認
kubectl get ccnp preview-isolation-guardrail -o yaml

# 5. 恒常的検証 CronJob の確認と即時手動テスト実行
kubectl get cronjob,job -n preview-isolation-test
kubectl create job --from=cronjob/preview-isolation-test manual-test-$(date +%s) -n preview-isolation-test
kubectl logs -n preview-isolation-test -l job-name --tail=50
```

## 7. 残存リスクと設計上の制限事項

多層防御を導入しても、Argo CD、Kubernetes、および Cilium の設計仕様上、以下の残存リスクが存在する：

1. **Namespace の名前制限（クラスタスコープリソース）**:
   - Argo CD の `spec.destinations` は Namespace スコープリソースを対象とするため、クラスタスコープである `kind: Namespace` 自体の名前（`metadata.name`）は destinations による prefix 制限（`pechka-pr-*` 等）を受けない。
   - 悪意ある PR がマニフェスト内で `metadata.name: pechka` 等の本番 Namespace を指定した場合、Server-Side Apply による設定競合や、PR クローズ時の prune により本番 Namespace が影響を受けるリスクが理論上残る。そのため、外部 PR に対する不用意なラベリングは避け、マニフェストの差分レビューを継続する。
2. **入口ラベル制御の TOCTOU / 遅延時のフェイルオープン**:
   - 第三者が悪意あるコミットを push してから GitHub Actions が起動して `preview` ラベルを剥奪するまでの間にわずかな時間差（窓）が存在する。この間に ApplicationSet のポーリング（`requeueAfterSeconds: 180`）が走った場合、悪意あるコミットの SHA でデプロイが試行される可能性がある。
   - GitHub Actions の障害や遅延、API エラー発生時、ラベルは剥奪されず維持される（fail-open）。
3. **ラベル自動再付与の振る舞い**:
   - 第三者がコミットを追加してラベルが剥奪された後、信頼された開発者（`k-wa-wa`）がその PR に対して push した場合、`auto-preview-label.yml` は再度 `preview` ラベルを自動付与する。第三者のコミットが残った状態で push すると第三者のコードがデプロイされるため、外部からのコミットが混入している PR を引き継ぐ際は、必ずコミット内容を精査した上で作業を行う。
4. **プレビュー環境間の通信と `pechka` 本番外部リソースへのピンポイント許可**:
   - `CiliumClusterwideNetworkPolicy` は単一のクラスタスコープポリシーであり、動的自己 Namespace 参照を持たないため、`pod-security.kubernetes.io/enforce: baseline` ラベルを持つプレビュー用 Namespace 同士の Pod 間通信は許容される（本番・システム Namespace からは完全に隔離される）。
   - また、`pechka` プレビューの動作要件上、本番 MinIO（`10.20.1.60:9000`）および初期シード用本番 PostgreSQL（`10.20.1.40:5432`）への TCP 通信は許可されているため、ネットワーク到達性自体はすべてのプレビュー環境に開かれている（認証情報は `pechka-preview-secret` により `pechka-pr-*` にのみ配布される）。
