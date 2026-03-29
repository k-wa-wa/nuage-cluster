# Grafana API 連携仕様設計

本設計は、Grafanaのダッシュボード上に、`Report Service`（Elasticsearchバックエンド）で管理しているAIサマリーを表示するためのAPI連携の仕組みを定義します。

## 1. なぜ API Integration が必要か

ElasticsearchはデフォルトでGrafanaのData Sourceとして機能しますが、インデックス生データを直接テーブルやパネルに表示すると、以下のような問題が生じます。

* 構造化されたAIサマリ（JSONのネストなど）が通常のログ検索パネルでは見づらい。
* 「類似する過去の障害履歴」など、Elasticsearchのベクトル検索を用いた特殊なクエリ結果を、Grafanaの標準クエリビルダーで作成するのが困難。
* 日本語の「提案アクションのリスト」などを専用のフォーマット（HTMLや特殊パネル）に整形して表示したい。

これを解消するため、`Report Service` 自体にHTTP APIエンドポイントを持たせ、Grafanaの **[Infinity Data Source Plugin](https://grafana.com/grafana/plugins/yesoreyeram-infinity-datasource/)** もしくは **JSON API Plugin** を通じてカスタムデータを取得・表示させます。

## 2. Report Service API (HTTP Endpoint) 設計案

`Report Service` は既存の gRPC エンドポイント（AI/Argoからの保存用）に加え、Grafana（UIアクセス用）のHTTPサーバをポート（例: `8080`）で公開します。

### 2.1 エラーサマリー一覧取得 API

* **Endpoint**: `GET /api/v1/reports`
* **機能**: 直近に発生したAIによるサマリ一覧を取得します。
* **Request Params**:
  * `limit` (int): 取得数
  * `time_range` (string): 検索対象期間
* **Response (JSON)**:
  ```json
  [
    {
      "id": "report-12345",
      "timestamp": "2026-03-28T08:00:00Z",
      "title": "[HIGH] DB Connection Timeout",
      "summary": "DBコネクション枯渇による遅延が発生しています。"
    }
  ]
  ```

### 2.2 サマリー本文＆類似障害検索 API

* **Endpoint**: `GET /api/v1/reports/:id/details`
* **機能**: 特定のサマリー詳細情報と、ベクトル的に特徴の似ている「過去の類似障害レポート」を合わせて返却します。
* **Response (JSON)**:
  ```json
  {
    "report": {
      "id": "report-12345",
      "root_cause": "...",
      "suggested_actions": ["..."]
    },
    "similar_issues": [
      {
        "id": "report-9999",
        "title": "[HIGH] 過去のDB Connection Timeout",
        "similarity_score": 0.95
      }
    ]
  }
  ```

## 3. Grafana ダッシュボードの実装指針

1. **データソースの設定**
   Grafanaのプラグイン設定から「Infinity Data Source」を追加し、URLに `http://report-service:8080` を指定します。
2. **パネル構成案**
   ダッシュボード上部に現在のLokiアラート、その直下にInfinity Pluginを利用した「AIからの診断結果（最新レポート）」を表示。
   クリックや変数フィルター（Variable）を用いて、対象レポートの `id` を連動させ、さらに下部のパネルで「類似障害ログ」などの付加情報を展開できるようなインタラクションを構築します。
