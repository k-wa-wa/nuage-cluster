## アーキテクチャ: Cilium + k8s + AIログサマリシステム

### コアコンセプト

* **Loki / Elasticsearch ベースのログ可観測性:** システムの中心はログ・メトリクスの集約基盤です。フロントエンド（UI）やユーザー認証/認可（RBAC）を廃止し、すべてGrafanaとElasticsearch/Lokiによる可観測性に特化します。
* **L7可視化と制御 (Cilium):** システムのセキュリティと可観測性はCiliumに依存します。Cilium Ingress / L7 Policy / BPF により通信をカーネルレベルで効率的に制御・可視化します。
* **AIによるログサマリとGrafana統合:** アプリケーションエラーや障害検知時、AIが自動で原因を要約します。その結果はElasticsearch/VectorDB等に保存され、Grafana経由で検索・閲覧が可能になります（類似エラー検索や日本語サマリ機能）。
* **Argo Workflowsによる非同期オーケストレーション:** トリガーを受けたあとの複雑な処理（データパイプライン構築、AI呼び出し、保存処理など）の現場監督としてArgoが機能します。

---

## 主要コンポーネント

1.  **Cilium (Ingress + L7 Policy + Network Visibility)**
    * **役割:** システムの「神経網」兼「高性能セキュリティゲート」。
    * **機能:**
        * **ルーティング:** Ingress を通じて外部トラフィックの流入を制御。Grafana等へのアクセスを中継。
        * **eBPFベースの可視化 (Hubble):** ホストのカーネルレベルで高速なパケットフィルタリングとL7ポリシー（HTTP等）を適用、システム全体の通信フローをリアルタイムで監視・監査。
        * **ネットワークポリシー:** `CiliumNetworkPolicy` により、サービス間の通信を最小権限原則 (Least Privilege) で制限します。

2.  **Trigger Service (gRPC + Webhook, 常駐)**
    * **役割:** エラー検知と処理開始の「起点」。
    * **機能:** サーバの主要な監視基盤（Loki + Alertmanager 等）から Webhook アラートを受信します。Argo Workflowをk8s API経由でSubmitし、即座に応答を返す（非同期キューイング代わり）ことでWebhookのタイムアウトを防ぎます。

3.  **Argo Workflows (k8s CRD)**
    * **役割:** **非同期オーケストレータ（現場監督）**。
    * **フロー:** `Trigger Service`から起動され、以下のステップを順次実行します。
        1.  `(Step 1)` `AI Service` をgRPCで呼び出し、ログデータを元にしたサマリ（根本原因の推定等）の生成を依頼。（同期的に完了を待つ）
        2.  `(Step 2)` `Report Service` をgRPCで呼び出し、Step 1で生成されたサマリを保存依頼。
        3.  `(Step 3)` `Notification Service` を呼び出し完了通知。

4.  **AI Service (gRPC, 常駐)**
    * **役割:** ログ分析・サマリ生成の**「頭脳」**。
    * **機能:**
        1.  LokiやElasticsearch等のクライアントを呼び出し、アラート対象時間帯のエラーログとメトリクスを収集。
        2.  収集データからLLM（大規模言語モデル）を呼び出し、日本語での原因推測サマリを生成。
        3.  （将来構想）グラフや解説図などの画像を生成・添付。
        4.  Argoに生成結果を返します。

5.  **Report Service (gRPC / API, 常駐)**
    * **役割:** サマリ・分析結果の永続化と、**Grafana向けデータソースAPI**。
    * **DB:** **Elasticsearch** などをプライマリデータベースとして使用。
    * **機能:**
        1.  Argoからのリクエストを受け、生成された日本語サマリや画像データを永続化。
        2.  Grafana（例えば JSON API Plugin や Infinity Plugin 等）から直接叩けるAPIエンドポイントを提供し、類似検索やダッシュボード上へのサマリー表示機能を提供します。

6.  **Notification Service (gRPC, 常駐)**
    * **役割:** 通知ディスパッチャ。
    * **機能:** Argo Workflowからの完了通知を受け、Slack / Discord / PagerDuty 等へ一括通知を行います。ユーザー個別の切り替え機能は持たず、システム共通の設定を用いシンプルなワーカーとして動作します。

7.  **Grafana (可視化統括プラットフォーム)**
    * **役割:** 以前の独自のWeb UIおよびGraphQL（APIGateway）を統合した唯一のダッシュボードプラットフォーム。
    * **機能:** ElasticsearchやLoki、Report Service をデータソースとして束ね、システムの状況とAIが生成した解決策を一元的に表示します。

---

## フローの整理

### アラート検知〜AI分析フロー (非同期)

1.  **[Loki / Alertmanager]** アプリのエラー率上昇等を検知し、Webhookを `Trigger Service` に送信。
2.  **[Trigger Service]** `Argo Workflow` をSubmitして即座に応答。
3.  **[Argo Workflow]** `AI Service` をgRPCで呼び出し。（Loki等からデータ収集 + LLMによる原因推定・日本語サマリ生成）。
4.  **[Argo Workflow]** `Report Service` をgRPCで呼び出し。（Elasticsearchへ保存）。
5.  **[Argo Workflow]** `Notification Service` をgRPCで呼び出し。
6.  **[Notification Service]** Slackへ通知を送信。

### Grafanaでの可視化・検索フロー

1.  **[オペレータ]** トラブル検知後、Grafanaを開く。
2.  **[Grafana]** 構築されたダッシュボードが `Report Service` のAPIやElasticsearchのインデックスを叩く。
3.  **[Report Service]** 対象時間帯のAI生成サマリや、類似の過去障害事象の検索結果をGrafanaに返却。
4.  **[オペレータ]** ダッシュボード上で「生のアラート」「関連メトリクス」「AIによる日本語ベースの根本原因分析」を同時に確認し、復旧対応を実施します。

---

## このアーキテクチャのメリット

* **不要な複雑性の排除**: ユーザー認証（RBAC/JWT）、独自のGraphQLサーバー（APIGateway）、フロントエンド層の実装・運用保守コストを全廃。Grafanaエコシステムに乗ることで可視化の拡張性が向上します。
* **高可用性・耐障害性の維持**: Argo Workflowsの信頼性の高いキュー・リトライコントロール、およびCiliumのカーネルレベル保護は継承されます。
* **運用の「AIコパイロット」化**: 「エラーの発生を知らせる」だけでなく「過去との類似性や根本原因の推論」を、見慣れたGrafanaのパネル上で直接提供できるようになり、属人化を排除できます。
