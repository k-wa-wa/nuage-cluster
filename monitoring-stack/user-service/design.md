# User Service 詳細設計

## 概要

User Service は、認証、権限キャッシュJWTの発行、およびユーザープロファイル管理を担当するgRPCサービスです。Kubernetes RBACと連携し、ユーザーの権限を宣言的に管理し、その情報をJWTクレームに埋め込むことで、システム全体の認可フローを効率化します。

## 役割

*   認証機能の提供
*   Kubernetes RBACに基づく権限の取得とJWTへの埋め込み
*   ユーザープロファイルの管理（通知設定、表示名など）

## API (gRPC)

### 1. `Login`

*   **機能:** ユーザー名とパスワードを受け取り、認証を行い、権限情報を含むJWTを発行します。
*   **リクエスト:** `LoginRequest`
    *   `username` (string): ユーザー名
    *   `password` (string): パスワード
*   **レスポンス:** `LoginResponse`
    *   `token` (string): 認証済みJWT
    *   `expires_in` (int64): JWTの有効期限（秒）

### 2. `GetUserProfile`

*   **機能:** 指定されたユーザーIDのプロファイル情報を取得します。
*   **リクエスト:** `GetUserProfileRequest`
    *   `user_id` (string): ユーザーID
*   **レスポンス:** `UserProfile`
    *   `user_id` (string): ユーザーID
    *   `display_name` (string): 表示名
    *   `notification_settings` (map<string, string>): 通知設定（例: `slack_url`, `email`）

### 3. `UpdateUserProfile`

*   **機能:** ユーザープロファイル情報を更新します。
*   **リクエスト:** `UpdateUserProfileRequest`
    *   `user_id` (string): 更新対象のユーザーID
    *   `display_name` (string, optional): 新しい表示名
    *   `notification_settings` (map<string, string>, optional): 新しい通知設定
*   **レスポンス:** `UpdateUserProfileResponse`
    *   `success` (bool): 更新が成功したか

## データモデル

### ユーザープロファイル (`UserProfile`)

*   `user_id` (string): ユーザーを一意に識別するID。Kubernetes `ServiceAccount`名と紐付けられます。
*   `display_name` (string): ユーザーの表示名。
*   `notification_settings` (map<string, string>): ユーザーごとの通知設定。例:
    ```json
    {
      "slack_url": "https://hooks.slack.com/services/...",
      "email": "user@example.com"
    }
    ```

## 内部処理フロー

### `Login` 処理フロー

1.  `LoginRequest` を受信 (`username`, `password`)。
2.  Kubernetes `Secret` から `username` に対応する `Secret` を検索。
3.  `Secret` 内の `passwordHash` とリクエストの `password` を比較し、認証。
4.  `Secret` から紐づく `serviceAccountName` を取得。
5.  この `serviceAccountName` を使用して、Kubernetes APIから関連する `RoleBinding` および `ClusterRoleBinding` を取得し、それらが参照する `Role` および `ClusterRole` の定義から権限ルールを収集します。
6.  収集した権限ルールを整形し、`permissions` クレームとして含むカスタムJWTを生成します。
7.  生成したJWTと有効期限を `LoginResponse` として返却。

### `GetUserProfile` / `UpdateUserProfile` 処理フロー

1.  リクエストを受信 (`user_id`, `display_name`, `notification_settings`)。
2.  PostgreSQL (または MySQL) データベースから `user_id` に対応するユーザープロファイル情報を取得/更新。
3.  結果をレスポンスとして返却。

## データベース

*   **PostgreSQL (または MySQL):** ユーザープロファイル情報（`display_name`, `notification_settings`など）を永続化するために使用します。

## セキュリティ考慮事項

*   **パスワードのハッシュ化:** `Secret`に保存されるパスワードはハッシュ化されていることを前提とします。
*   **JWTの署名:** JWTはセキュアな秘密鍵で署名され、Istioによって検証されます。
*   **Kubernetes RBAC:** 権限の信頼の基点としてKubernetes RBACを使用し、`SubjectAccessReview`を通じて動的に権限を評価します。
*   **mTLS:** サービス間の通信はIstio mTLSによって保護されます。
