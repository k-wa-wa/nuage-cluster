# プレビュー環境のセキュリティ設計と多層防御

公開リポジトリ（`pechka`, `bare-web-proxy`, `nuage-monitoring-stack`）の PR を自動デプロイする Argo CD Preview ApplicationSet における、外部からの不正デプロイ遮断とクラスタ保護の設計メモである。

## 多層防御の構成

1. **入口制御**: PR に `preview` ラベルがあるものだけを対象にする（アプリ側 `.github/workflows/auto-preview-label.yml` が `k-wa-wa` / `bot-wa-wa` のみ自動付与、第三者活動で剥奪。Argo CD 側は `manifests/apps/*-preview-appset.yaml` でフィルタ）。
2. **Argo CD 制限**: `preview-apps` AppProject により、デプロイ先を各 PR 専用 Namespace、Cluster スコープ許可を `Namespace` のみ、Namespace スコープも許可リストに限定する（`manifests/apps/preview-project.yaml`）。
3. **ノード保護**: 各 Preview ApplicationSet の Kustomize パッチで Namespace に Pod Security Admission `baseline` ラベルを付与し、特権コンテナや `hostNetwork`・`hostPath` を拒否する（`manifests/apps/*-preview-appset.yaml`）。
4. **ネットワーク隔離**: `CiliumClusterwideNetworkPolicy` (`preview-isolation-guardrail`) で `baseline` ラベル付き Namespace を捕捉し、自宅 LAN・クラスタ内部・`kube-apiserver`・本番/システム Namespace への横展開を遮断する。CoreDNS、インターネット、`pechka` プレビュー用外部実ノード（SeaweedFS S3 / PostgreSQL）、および `nuage-honeytrap` への誘導通信のみを許可する（`manifests/apps/preview-network-policy.yaml`）。
5. **恒常的検証**: `preview-isolation-test` Namespace で 15 分おきにネットワーク遮断・許可とコンテナ境界を検証する（`manifests/apps/preview-isolation-test/base/cronjob.yaml`, `manifests/apps/preview-isolation-test/base/run-isolation-test.sh`）。

## 残存リスクと設計上の制限事項

1. **Namespace 名制限の欠如とラベルパッチ空振りリスク**:
   - Argo CD の `spec.destinations` は `kind: Namespace` 自身の `metadata.name` を制限できないため、悪意ある PR が `metadata.name: pechka` 等の本番 Namespace を指定すると Server-Side Apply の競合や PR クローズ時の prune で本番 Namespace が影響を受けるおそれがある。また、現在の Preview ApplicationSet はアプリ側の `Namespace` マニフェストへ Kustomize パッチで PSA ラベルを付与しているため、PR 側で `Namespace` 定義が削除・改名されるとパッチが空振りし、ラベル無しの `*-pr-*` Namespace が作られて PSA と `CiliumClusterwideNetworkPolicy` の捕捉対象から外れるリスクがある。
   - 恒久対策は `syncPolicy.managedNamespaceMetadata` または `ValidatingAdmissionPolicy` によるラベル強制である。それまでは `k8s/` 配下のマニフェスト差分レビューを継続する。
2. **入口ラベル制御の TOCTOU・フェイルオープン・再付与**:
   - 第三者がコミットを push してから `auto-preview-label.yml` が `preview` ラベルを剥奪するまでの短い窓に ApplicationSet のポーリング（`requeueAfterSeconds: 180`）が重なった場合や、GitHub Actions の遅延・障害時はラベルが維持される（fail-open）。
   - 第三者コミットでラベルが剥奪された後、信頼された開発者がその PR に push すると `preview` ラベルが再付与されるため、引き継ぎ時は既存の全コミットを精査する。
3. **プレビュー環境間の相互到達性と `pechka` シード DB・外部リソース**:
   - `CiliumClusterwideNetworkPolicy` は動的自己 Namespace 参照を持たないため、`baseline` ラベル付きプレビュー Namespace 間は相互に通信できる。他プレビュー環境から `pechka-pr-*` のローカル `postgres`（本番からのシードデータを含み、接続情報が公開リポに平文記載）へ到達できるリスクが残る。
   - また、本番 SeaweedFS S3（`10.20.1.61〜63:9000`）および本番 PostgreSQL（`10.20.1.41〜43:5432`）への TCP 到達性自体は全プレビュー環境に開かれている（本番 DB 認証情報は `pechka-preview-secret` で `pechka-pr-*` のみに配布）。
4. **`kube-apiserver` 遮断による `pechka` プレビューのワークフロー制限**:
   - `toEntities: [kube-apiserver]` を遮断しているため、`pechka` プレビュー環境で `api` が Argo Workflows の `Workflow` リソースを生成・実行する機能（ingest / upload 時の ETL・字幕生成）は動作しない。必要時は RBAC スコープ精査の上で `kube-apiserver`（`6443/TCP`）許可を別途検討する。
