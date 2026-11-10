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
4. **ネットワーク隔離ガードレールと恒常的検証 (Layer 5: `CiliumClusterwideNetworkPolicy` & `CronJob`)**:
   - クラスタ全体のガードレールとして `CiliumClusterwideNetworkPolicy` (`preview-isolation-guardrail`) を配置し、`pod-security.kubernetes.io/enforce: baseline` ラベルが付与された Preview Namespace の Pod を捕捉する。
   - 自宅 LAN（`192.168.0.0/16`：Proxmox, PBS, ルータ等）、クラスタ内部ゾーン（`10.0.0.0/8`：k8s ノード, Talos API, etcd 等）、`kube-apiserver`（`10.96.0.1:443`）、プライベート・CGNAT・リンクローカル帯、および本番・システム Namespace（`argocd`, `pechka` 本番, `kube-system` 等）への通信（横展開）を全面遮断する。
   - プレビュー環境内の Pod 間通信、Ingress Controller からの流入、CoreDNS（`53/UDP`, `53/TCP`）による名前解決、パブリックインターネット通信、および `pechka` プレビューが参照する本番外部リソース（MinIO `10.20.1.60:9000/TCP`、初期シード用 PostgreSQL `10.20.1.40:5432/TCP`）のみをピンポイントで許可する。
   - クラスタ内部探索を試みた攻撃者を早期かつ誤検知ゼロで検知するトラップ導線として、独立した Namespace で稼働するマルチプロトコル侵入検知ハニーポット（`nuage-honeytrap`）への限定 Egress を明示的に許可する。
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

`preview-apps` AppProject からは変更・削除できない `nuage-cluster` 側のクラスタスコープリソース（`CiliumClusterwideNetworkPolicy`: `preview-isolation-guardrail`）として配置する。

- **捕捉条件 (`endpointSelector`)**:
  - `io.cilium.k8s.namespace.labels.pod-security.kubernetes.io/enforce: baseline`
  - Preview Namespace に付与される PSA `baseline` ラベルをセレクタとして対象 Pod を捕捉する（アプリ側マニフェスト改変による Namespace ラベル回避リスクについては §7.1 を参照）。
- **Ingress 制御**:
  - プレビュー環境（`baseline` ラベル付き Namespace）内の Pod 間通信を許可。
  - Cilium Ingress (`fromEntities: [ingress]`) からの HTTP/HTTPS トラフィック流入を許可。
- **Egress 制御**:
  - プレビュー環境（`baseline` ラベル付き Namespace）内の Pod 間通信を許可。なお、`CiliumClusterwideNetworkPolicy` はクラスタスコープであるため、空の `matchLabels: {}` を指定するとクラスタ内の全 Namespace（`argocd` や本番 Namespace を含む）への通信が許可されてしまう。これを防ぐため、`toEndpoints` / `fromEndpoints` にも `io.cilium.k8s.namespace.labels.pod-security.kubernetes.io/enforce: baseline` を指定し、本番・システム Namespace への横展開を遮断する。
  - `kube-system` Namespace の CoreDNS (`k8s-app: kube-dns`) に対する `53/UDP` および `53/TCP` のみ許可。
  - `toCIDRSet` により `0.0.0.0/0` からプライベート IP 帯（`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, `100.64.0.0/10`, `169.254.0.0/16`）を除外し、パブリックインターネットへの通信のみを許可。
  - `pechka` プレビュー環境が必要とする本番 MinIO（SeaweedFS S3 VIP: `10.20.1.60/32` Port `9000/TCP`）および初期シード用本番 PostgreSQL（VIP: `10.20.1.40/32` Port `5432/TCP`）への Egress のみピンポイントで許可。
  - 侵入検知ハニーポット（`nuage-honeytrap`）への限定 Egress 許可（`toEndpoints` による `io.kubernetes.pod.namespace: nuage-honeytrap`）。プレビュー環境からクラスタ内部への横展開やポートスキャンを試みた攻撃者を確実にハニーポットへ誘引し、早期かつ誤検知ゼロで検知・アラート発報するトラップ導線として機能させる（`nuage-honeytrap` は PSA `restricted` 準拠の非特権 Namespace で動作し、万一侵害されても被害が波及しない設計）。

### 5.2 恒常的セキュリティ検証 CronJob (`manifests/apps/preview-isolation-test/`)

ネットワークポリシーの適用漏れや Cilium 設定変更時の構成ドリフト、ならびにコンテナランタイム（containerd/Talos）における既定セキュリティ境界（Masked/Read-Only パス、デバイス隔離、特権ケーパビリティ非付与）の設定ドリフトを継続的に検知するため、`preview-isolation-test` Namespace に `CronJob` (`preview-isolation-test`) を常設する。
スクリプト本体は shellcheck による静的解析を維持するため `run-isolation-test.sh` として独立ファイルで管理し、Kustomize の `configMapGenerator` 経由で ConfigMap に展開する。

- **スケジュール**: 15 分おき（`*/15 * * * *`、`concurrencyPolicy: Forbid`）
- **ジョブ制御と耐障害性**:
  - `imagePullPolicy: IfNotPresent` を明示し、Docker Hub への毎回 pull による遅延や外部レート制限による失敗を防止する。
  - `activeDeadlineSeconds: 180` により、検証項目拡充に伴うタイムアウトを緩和しつつハングを防止する。
  - `failedJobsHistoryLimit: 1` により、古い失敗履歴を最新 1 件のみ保持する（変更前の 3 件から削減）。
  - `ttlSecondsAfterFinished: 86400`（24時間）により、完了・失敗した Job を自動クリーンアップする。Kubernetes CronJob は成功と失敗の履歴を独立してカウントするため、一度失敗した Job は後続 Job が成功しても即座には削除されず、TTL（最大 24 時間）経過または次の失敗発生まで残存する。これにより Grafana 壁掛けモニター等の `KubeJobFailed` アラートは最大 24 時間で自動解消される（※より迅速なアラート解消が必要な場合は、TTL 短縮や Prometheus アラート条件の見直しを検討する）。
- **検証項目 (`run-isolation-test.sh`)**:
  - Cilium によるパケット drop は必ずタイムアウトになるため、遮断テストでは `nc -z -vv -w 3` の出力が `Connection timed out`（かつ終了コード非 0）となった場合のみを PASS とし、それ以外（疎通成功、相手ホストからの TCP RST / `Connection refused`、`No route to host`、名前解決失敗等）はすべてポリシー未機能として FAIL 扱いにする。
  1. **遮断テスト（自宅 LAN / PBS `192.168.5.30:8007`）**: `Connection timed out`（drop）なら PASS、それ以外（疎通・`Connection refused`・到達不能応答等）は FAIL。
  2. **遮断テスト（k8s コントロールプレーン / Talos API `10.20.1.11:50000`）**: `Connection timed out`（drop）なら PASS、それ以外は FAIL。
  3. **遮断テスト（ノード Kubelet API `10.20.1.11:10250`）**: Kubelet 認証回避やノード上 Pod 情報の奪取を遮断。`Connection timed out` なら PASS。
  4. **遮断テスト（Cilium ヘルスチェックポート `10.20.1.11:4240`）**: ノードヘルスエンドポイント経由の内部プローブを遮断。`Connection timed out` なら PASS。
  5. **遮断テスト（クラウド／リンクローカルメタデータ `169.254.169.254:80`）**: クラウドメタデータ API（IMDS）やリンクローカル宛先へのアクセスを遮断。`Connection timed out` なら PASS。
  6. **遮断テスト（k8s API サーバー `10.96.0.1:443`）**: `Connection timed out`（drop）なら PASS、それ以外は FAIL。
  7. **遮断テスト（他 Namespace / Argo CD Server `argocd-server.argocd.svc.cluster.local:80`）**: `Connection timed out`（drop）なら PASS、それ以外は FAIL。
  8. **許可テスト（CoreDNS `10.96.0.10:53` TCP および `nslookup` UDP 名前解決）**: 両方成功すれば PASS、いずれか失敗なら FAIL。
  9. **許可テスト（パブリックインターネット `1.1.1.1:443`）**: 疎通すれば PASS、遮断されれば FAIL。
  10. **許可テスト（`pechka` 本番外部リソース：MinIO VIP `10.20.1.60:9000` および PostgreSQL VIP `10.20.1.40:5432`）**: 両方疎通すれば PASS、いずれか遮断されれば FAIL。
  11. **コンテナ境界テスト（Masked / Read-Only パス）**: `/proc/self/mountinfo` で `/proc/sys` および `/sys` が `ro` マウントされていることを確認した上で、書き込み試行が `Read-only file system` (EROFS) で拒否されることを検証。コンテナエスケープの起点となるホストカーネルパラメータ改ざん（`sysctl` や `sysfs` 経由）を防止する設計意図。
  12. **コンテナ境界テスト（ホスト生ブロックデバイス非露出）**: `/dev/` 配下にホストの生ブロックデバイス（`sda*`, `vda*`, `nvme*`, `xvd*`, `dm-*` 等）が存在しないことを検証。ストレージ生パーティションの直接マウントや破壊を防止する設計意図。
  13. **コンテナ境界テスト（Linux 特権ケーパビリティ非保持）**: `/proc/self/status` の `CapEff` を読み取り、`CAP_SYS_ADMIN`（`0x00200000`）をはじめとする危険な特権ケーパビリティ（`CAP_SYS_MODULE`, `CAP_SYS_RAWIO`, `CAP_SYS_PTRACE`, `CAP_SYS_BOOT`）が付与されていないことを検証。非特権コンテナに対する containerd/Talos ランタイム既定値のドリフトを検知する設計意図（※本検証 Pod 自体は特権を要求しないため、PSA admission による特権 Pod 拒否そのものを検証するものではない点に留意）。
- 1 つでも違反があればスクリプトは Exit 1 で終了し、Job が `Failed` 状態として記録される。

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

1. **Namespace の名前制限および Kustomize パッチによるラベル付与の回避リスク**:
   - Argo CD の `spec.destinations` は Namespace スコープリソースを対象とするため、クラスタスコープである `kind: Namespace` 自体の名前（`metadata.name`）は destinations による prefix 制限（`pechka-pr-*` 等）を受けない。
   - 悪意ある PR がマニフェスト内で `metadata.name: pechka` 等の本番 Namespace を指定した場合、Server-Side Apply による設定競合や、PR クローズ時の prune により本番 Namespace が影響を受けるリスクが理論上残る。
   - さらに、現在の各 Preview ApplicationSet はアプリリポジトリ内の `kind: Namespace`（`pechka-preview` 等）をターゲットとして Kustomize パッチで `pod-security.kubernetes.io/enforce: baseline` ラベルを付与している。PR 側で `Namespace` マニフェスト自体を削除または改名した場合、Kustomize パッチはエラーにならず空振りし、`CreateNamespace=true`（または Kustomize の namespace 変換）によって**ラベル無しの `*-pr-*` Namespace** が生成され、PSA および `CiliumClusterwideNetworkPolicy` の捕捉対象から外れるリスクがある。
   - 恒久的な対策としては、ApplicationSet の `syncPolicy.managedNamespaceMetadata` によるラベル強制、または Kubernetes の `ValidatingAdmissionPolicy` で `*-pr-*` Namespace に `pod-security.kubernetes.io/enforce: baseline` ラベルを必須化する構成が有効である。それまでは外部 PR に対する不用意なラベリングを避け、`k8s/` 配下のマニフェスト差分レビューを継続する。
2. **入口ラベル制御の TOCTOU / 遅延時のフェイルオープン**:
   - 第三者が悪意あるコミットを push してから GitHub Actions が起動して `preview` ラベルを剥奪するまでの間にわずかな時間差（窓）が存在する。この間に ApplicationSet のポーリング（`requeueAfterSeconds: 180`）が走った場合、悪意あるコミットの SHA でデプロイが試行される可能性がある。
   - GitHub Actions の障害や遅延、API エラー発生時、ラベルは剥奪されず維持される（fail-open）。
3. **ラベル自動再付与の振る舞い**:
   - 第三者がコミットを追加してラベルが剥奪された後、信頼された開発者（`k-wa-wa`）がその PR に対して push した場合、`auto-preview-label.yml` は再度 `preview` ラベルを自動付与する。第三者のコミットが残った状態で push すると第三者のコードがデプロイされるため、外部からのコミットが混入している PR を引き継ぐ際は、必ずコミット内容を精査した上で作業を行う。
4. **プレビュー環境間の相互到達性と `pechka` シード済み DB・本番外部リソースへの到達性**:
   - `CiliumClusterwideNetworkPolicy` は単一のクラスタスコープポリシーであり動的自己 Namespace 参照を持たないため、`fromEndpoints` / `toEndpoints` により `pod-security.kubernetes.io/enforce: baseline` ラベルを持つプレビュー用 Namespace 間の通信は相互に許可される（本番・システム Namespace からは隔離される）。
   - このため、別リポジトリや別 PR のプレビュー環境から `pechka-pr-*` 内の全 Pod・全ポートへ到達可能である。`pechka-pr-*` のローカル `postgres` には `postgres-seed-from-prod` Job により本番 DB からコピーされたデータが格納されており、かつその接続情報は公開リポジトリの `k8s/overlays/preview/local-secrets.yaml` に平文で記載されているため、同時に稼働している他のプレビュー環境から本番データの写しを読み取られるリスクが残る。
   - また、`pechka` プレビューの動作要件上、本番 MinIO（`10.20.1.60:9000`）および初期シード用本番 PostgreSQL（`10.20.1.40:5432`）への TCP 通信は許可されているため、ネットワーク到達性自体はすべてのプレビュー環境に開かれている（本番 PostgreSQL の認証情報は `pechka-preview-secret` により `pechka-pr-*` にのみ配布される）。
5. **`kube-apiserver` への Egress 遮断に伴う `pechka` プレビューのワークフロー実行制限**:
   - プレビュー環境から Kubernetes API サーバー（`kubernetes.default` / `10.96.0.1:443` / コントロールプレーン `6443/TCP`）への Egress は、`toEntities: [kube-apiserver]` を許可せず意図的に遮断している。
   - そのため、`pechka` プレビュー環境において `api`（ServiceAccount `api-sa`）が Kubernetes API を呼び出して Argo Workflows の `Workflow` リソースを生成する機能（ingest・upload 時の `etl-bluray` / `subtitle-gen` 起動）および Workflow Pod（emissary）の API 通信は遮断され、プレビュー環境でのワークフロー実行は動作しない制限事項となる。プレビュー環境でワークフロー実行が必要になった場合は、RBAC スコープを精査した上で `toEntities: [kube-apiserver]`（Port `6443/TCP`）の追加を別途検討する。
