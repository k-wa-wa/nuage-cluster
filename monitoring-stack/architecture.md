## アーキテクチャ: Istio + k8s RBAC + GraphQLベースのAI監視システム

### コアコンセプト

* **信頼の基点 (SoT):** アプリケーションの**権限（誰が何できるか）**は、Kubernetesの`ClusterRole`と`RoleBinding`によって**宣言的に定義**されます。これが唯一の信頼の基点です。
* **認証と権限のキャッシュ:** ログイン時に**一度だけ**k8s RBACを`SubjectAccessReview` (SAR) で確認し、許可された権限リストを**JWTクレームに埋め込み**ます。
* **実行とゼロスト:**
    1.  **Istio**がシステム全体の入り口（Ingress）として動作し、**JWT署名検証（認証）**と、`APIGateway Service`への大枠のアクセス制御を行います。
    2.  **APIGateway Service (GraphQL)**が、JWTの`permissions`クレームを**ロジックとして検証**し、フィールドレベルの高速な**認可**を実行します。
    3.  内部サービス（gRPC）はロジックに専念し、Istio mTLSによって保護されます。

---

## 主要コンポーネント

1.  **Istio (Ingress Gateway + Service Mesh)**
    * **役割:** システムの「神経網」兼「中央ゲート」。
    * **機能:**
        * **ルーティング:** `APIGateway Service`へのHTTP/S (GraphQL) および内部gRPCのリクエストを転送します。
        * **認証 (`RequestAuthentication`):** すべての着信リクエストのJWT署名を検証します。
        * **認可 (`AuthorizationPolicy`):** `/graphql` エンドポイントへのアクセスを、**認証済みユーザーのみに限定**します。（フィールドレベルの認可は行わない）
        * **mTLS:** サービス間のすべてのgRPC通信を自動的に暗号化し、ゼロストな内部ネットワークを実現します。

2.  **User Service (gRPC, 常駐)**
    * **役割:** 認証、「権限キャッシュJWT」の発行、およびユーザープロファイル管理。
    * **機能:**
        1.  `login(user, pass)` リクエストを受信。
        2.  k8s `Secret`から`username`を検索し、`passwordHash`を検証。
        3.  `Secret`から紐づく`serviceAccountName`を取得。
        4.  このSAを使い、アプリの全権限についてk8s APIに**`SubjectAccessReview`を一括実行**。
        5.  許可された権限リストを`permissions`クレームとして含む**カスタムJWTを発行**します。
        6.  `GetUserProfile`, `UpdateUserProfile` などのAPIを提供し、専用DB（下記参照）の通知設定などを管理します。

3.  **Trigger Service (gRPC + Webhook, 常駐)**
    * **役割:** レポート作成の「きっかけ」を受け付けます。
    * **機能:** Alertmanager Webhook、Cron、または`APIGateway Service`経由の手動APIリクエストを受け取り、パラメータを整えて`Argo Workflow`をk8s API経由でSubmitします。**即座に応答を返す**ことでWebhookのタイムアウトを防ぎます。

4.  **Argo Workflows (k8s CRD)**
    * **役割:** **非同期オーケストレータ（現場監督）**。
    * **フロー:** `Trigger Service`から起動され、以下のステップを順次実行します。
        1.  `(Step 1)` `AI Service` をgRPCで呼び出し、レポート生成を依頼。（同期的に完了を待つ）
        2.  `(Step 2)` `Report Service` をgRPCで呼び出し、Step 1で生成されたレポートを保存。
        3.  `(Step 3)` `Notification Service` をgRPCで呼び出し、ユーザーに完了通知。

5.  **Report Service (gRPC, 常駐)**
    * **役割:** レポートの永続化(CRUD)と検索。
    * **DB:** **Elasticsearch** をプライマリデータベースとして使用します。
    * **API:** `CreateReport` (Argoから), `GetReport`, `ListReports` (APIGatewayから) など。

6.  **AI Service (gRPC, 常駐)**
    * **役割:** レポート生成の**「頭脳」**。チケット制のゲートキーパー兼、データ収集・AI実行を担当します。
    * **機能:** ArgoからのgRPCリクエストに基づき、以下の処理を**内部で**実行します。
        1.  **レート制限:** **Redis**を参照し、ユーザーごとのチケット残高をチェック・消費 (`DECR`)。
        2.  **MCPロジック:** **内部モジュールとして**k8sやLokiのクライアントを呼び出し、データ収集。
        3.  **LLM呼び出し:** 収集データからレポート本文を生成。
        4.  Argoにレポート本文を返します。

7.  **Notification Service (gRPC, 常駐)**
    * **役割:** Argo Workflowからの依頼に基づき、通知を送信します。
    * **機能:**
        1.  Argoからリクエスト（例: `userId`）を受信。
        2.  `User Service`にgRPCで`GetUserProfile`をリクエストし、通知先（Slack URLなど）を取得。
        3.  通知を実行。

8.  **APIGateway Service (GraphQL, 常駐)**
    * **役割:** フロントエンドUIのためのGraphQL集約エンドポイント。
    * **機能:**
        1.  UIから単一エンドポイント（`/graphql`）でリクエストを受信。
        2.  Istioが検証済みのJWTヘッダを読み取り、`permissions`クレームを取得。
        3.  **GraphQLリゾルバのロジック内部で、フィールドレベルの認可を実行**。（例: `reports`フィールドの要求に対し、クレームに`reports:list`があるか確認）
        4.  権限が確認された場合のみ、`Report Service`や`User Service`などの内部gRPCを呼び出し、データを集約してUIに返します。

9.  **Frontend (UI)**
    * **役割:** ユーザーが閲覧するダッシュボード (React, Vueなど)。Istio Ingress Gateway経由で`User Service` (ログイン) や `APIGateway Service` (データ) と通信します。

10. **Kubernetes RBACリソース (IAMの定義)**
    * `ClusterRole`: アプリ権限（例: `report-reader`）を仮想リソース (`ai-reporter.myapp.com/reports`) に対して定義します。
    * `ServiceAccount`: ユーザーID（例: `user-alice-sa`）として機能します。
    * `Secret`: ユーザーの認証情報（`username`, `passwordHash`, `serviceAccountName`）を格納します。
* `RoleBinding`: `user-alice-sa` と `report-reader` を紐付けます。

11. **基盤データベース**
    * **Redis:** `AI Service`のレート制限（チケット残高）管理用。
    * **Elasticsearch:** `Report Service`のレポートデータ保存・検索用。
    * **PostgreSQL (または MySQL):** `User Service`が使用する、ユーザープロファイル（通知設定、表示名など）の管理用。

---

## フローの整理

### 認証・認可フロー

1.  **[管理者]** `kubectl apply` で、`ClusterRole`, `ServiceAccount`, `Secret`, `RoleBinding` を作成し、ユーザー (`alice`) に権限 (`report-reader`) を付与します。
2.  **[ユーザー]** UIから `alice` とパスワードでログイン。
3.  **[User Service]** `Secret`でパスワードを検証。k8s APIに`SubjectAccessReview`を投げ、`alice`の権限が `["reports:list", "reports:get"]` であることを確認。
4.  **[User Service]** `permissions: ["reports:list", "reports:get"]` というクレームを含んだJWTを発行し、ユーザーに返します。
5.  **[ユーザー]** レポート一覧を含むGraphQLクエリを、JWTをヘッダに付与して `APIGateway Service` (`/graphql`) にリクエスト。
6.  **[Istio Ingress Gateway]** リクエストを受信。
    * (Authn) JWTの署名を検証。
    * (Authz) `AuthorizationPolicy`に基づき、`/graphql` エンドポイントへのアクセスを許可。
    * (Routing) リクエストを`APIGateway Service`に転送。
7.  **[APIGateway Service]**
    * (Authz) GraphQLリゾルバが、リクエストされた`reports`フィールドに対し、JWTの`permissions`クレームに `reports:list` が**含まれているかロジックで検証**。
    * (Logic) 権限があるため、`Report Service`にgRPCで `ListReports` をリクエスト。
    * 結果をUIに返します。

### レポート作成フロー (非同期)
1.  **[Alertmanager]** Webhookを `Trigger Service` に送信。
2.  **[Trigger Service]** `Argo Workflow` をSubmit。（即座に応答）
3.  **[Argo Workflow]** `AI Service` をgRPCで呼び出し。（AIがMCP実行 + LLM生成）
4.  **[Argo Workflow]** `Report Service` をgRPCで呼び出し。（Elasticsearchへ保存）
5.  **[Argo Workflow]** `Notification Service` をgRPCで呼び出し。
6.  **[Notification Service]** `User Service` から通知先を取得し、ユーザーへ通知。

---

## このアーキテクチャのメリット

* **大袈裟（学習に最適）:** マイクロサービス、gRPC、GraphQL、Argo、Istio、k8s RBACの連携という、非常に高度でモダンなスタック全体を学習・検証できます。
* **宣言的な権限管理:** アプリの「誰が何できるか」を、コードではなくk8sのRBAC (YAML) で一元管理できます。
* **効率的なデータ取得:** `APIGateway Service` (GraphQL) により、UIは必要なデータを一度のリクエストで効率的に取得できます。
* **厳格なゼロスト:** IstioがJWT認証とmTLSによるサービス間暗号化を強制します。
* **柔軟な認可:** `APIGateway Service`がGraphQLリゾルバ内でクレームを検証することで、フィールドレベルの柔軟な認可制御を実現します。
* **スケーラビリティ:** 各コンポーネント（特に`AI Service`やArgoのWorkflow実行Pod）を個別にスケールできます。
* **信頼性:** Argo Workflowが非同期処理、リトライ、可観測性を担保します。
