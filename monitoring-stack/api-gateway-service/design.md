# APIGateway Service 詳細設計

## 概要

APIGateway Service は、フロントエンドUIのためのGraphQL集約エンドポイントです。Istioによって検証済みのJWTヘッダを読み取り、`permissions`クレームに基づいてフィールドレベルの認可を実行し、内部gRPCサービス（User Service, Report Serviceなど）を呼び出してデータを集約し、UIに返却します。

## 役割

*   GraphQLエンドポイントの提供
*   JWT `permissions`クレームに基づくフィールドレベルの認可
*   内部gRPCサービスへのリクエストのルーティングとデータ集約

## API (GraphQL)

単一のGraphQLエンドポイント `/graphql` を提供します。

### スキーマ定義 (抜粋)

```graphql
schema {
  query: Query
  mutation: Mutation
}

type Query {
  me: UserProfile
  reports: [Report!]!
  report(id: ID!): Report
}

type Mutation {
  login(username: String!, password: String!): LoginPayload!
  updateUserProfile(displayName: String, notificationSettings: [NotificationSettingInput!]): UserProfile!
}

type UserProfile {
  id: ID!
  displayName: String!
  notificationSettings: [NotificationSetting!]!
}

type NotificationSetting {
  key: String!
  value: String!
}

input NotificationSettingInput {
  key: String!
  value: String!
}

type LoginPayload {
  token: String!
  expiresIn: Int!
}

type Report {
  id: ID!
  title: String!
  content: String!
  createdAt: String!
}
```

## 内部処理フロー

### 1. GraphQLリクエストの受信

*   UIから `/graphql` エンドポイントへのリクエストを受信。
*   IstioによってJWTの署名検証と大枠の認可（認証済みユーザーのみ）が完了していることを前提とします。

### 2. JWT `permissions`クレームの取得

*   リクエストヘッダからJWTを抽出し、`permissions`クレームをデコードして取得します。

### 3. フィールドレベルの認可

*   GraphQLリゾルバ内で、リクエストされたフィールド（例: `Query.reports`, `Mutation.updateUserProfile`）に対し、JWTの`permissions`クレームに適切な権限（例: `reports:list`, `user:update`）が含まれているかロジックで検証します。
*   権限がない場合は、GraphQLエラーを返却します。

### 4. 内部gRPCサービスの呼び出しとデータ集約

*   認可が成功した場合、対応する内部gRPCサービスを呼び出します。
    *   `Query.me` -> `User Service.GetUserProfile`
    *   `Query.reports` -> `Report Service.ListReports`
    *   `Query.report(id)` -> `Report Service.GetReport`
    *   `Mutation.login` -> `User Service.Login`
    *   `Mutation.updateUserProfile` -> `User Service.UpdateUserProfile`
*   複数のgRPCサービスからのデータを集約し、GraphQLのレスポンス形式に変換してUIに返却します。

## 依存サービス

*   **User Service (gRPC):** 認証、ユーザープロファイル情報の取得・更新に使用。
*   **Report Service (gRPC):** レポート情報の取得に使用。
*   **Istio:** JWT認証、mTLSによるサービス間通信の保護。

## セキュリティ考慮事項

*   **JWT検証:** IstioがJWTの署名検証を行うため、APIGateway Serviceではクレームの検証に集中します。
*   **フィールドレベル認可:** GraphQLリゾルバ内で細粒度な認可ロジックを実装し、不正なデータアクセスを防ぎます。
*   **mTLS:** 内部gRPCサービスとの通信はIstio mTLSによって保護されます。
