# アラートワークフロー仕様設計

Lokiからのアラートを起点とし、AIサマリ生成までを非同期で実行するエンドツーエンドのワークフロー設計です。

## 1. 全体アーキテクチャフロー

1. **LogQL Alerting (Loki / Alertmanager)**
   エラーログ文字列の一致やメトリクスの閾値超過などの条件により、AlertmanagerからWebhook（HTTP POST）が発火します。
2. **Trigger Service の受信**
   WebhookのJSONペイロードを受け取り、必要なメタデータ（サービス名、アラート期間、生ログのサンプリング情報など）を正規化し、Argo Workflow用のパラメータとしてバインドします。
3. **Argo Workflows の起動**
   `Trigger Service` はK8sの `Workflow` カスタムリソースを作成（Submit）し、HTTPレスポンスとして `202 Accepted` を即座にAlertmanagerへ返します（非同期化）。
4. **Job実行 (AI Service -> Report Service -> Notification Service)**
   ArgoのDAG（有向非巡回グラフ）またはStepsで構成されたジョブが順次実行されます。

## 2. 実装に向けた要件

### Trigger Service
* **エンドポイント機能**: Alertmanagerの規定するWebhookペイロードスキーマ (`version: "4"`) に対応したエンドポイント `/webhook` の実装。
* **パラメータ抽出**:
  アラートの `Labels` (例えば `app="frontend"`, `namespace="production"`) と `Annotations` (アラートの要約文) を抽出し、JSONにまとめてArgoのリファレンスに渡します。
* **CRD操作**:
  k8sの `client-go` などを利用して、`namespace: argo` に新しい `Workflow` を生成・Submitする権限とロジックの実装。

### Argo Workflow の定義 (job-service)
`/report-generation-workflow.yaml` のようなWorkflowTemplateを事前に反映しておき、以下のようにパラメータを受け取るように構成します。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: WorkflowTemplate
metadata:
  name: ai-alert-analyzer
spec:
  arguments:
    parameters:
    - name: alertData
  entrypoint: main-flow
  templates:
  - name: main-flow
    steps:
    - - name: generate-summary
        template: ai-analysis-job
        arguments:
          parameters:
          - name: alertContext
            value: "{{workflow.parameters.alertData}}"
```

### 3. 今後の課題・拡張性
* 大量のアラート（アラートストーム）発生時、すべてに対してAIジョブを生成するか、`Trigger Service` 側で重複排除（デバウンス処理）を行うか、あるいはAlertmanager側のグルーピング設定を厳しめにするかの調整が必要です。まずは Alertmanager の `group_by` の設定でコントロールすることを推奨します。
