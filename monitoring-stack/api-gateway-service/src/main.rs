use async_graphql::{EmptySubscription, Schema};
use async_graphql_warp::GraphQLResponse;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::convert::Infallible;
use tonic::transport::Channel;
use warp::Filter;
use std::sync::Arc;
use tokio::sync::Mutex;

mod proto {
    pub mod user_service {
        tonic::include_proto!("user_service");
    }
}

use proto::user_service::{
    user_service_client::UserServiceClient, GetUserProfileRequest, LoginRequest,
    UpdateUserProfileRequest,
};

#[derive(Debug, Serialize, Deserialize, Clone)]
struct Claims {
    sub: String,
    iss: String,
    aud: Vec<String>,
    permissions: Vec<String>,
    #[serde(rename = "serviceAccountName")]
    service_account_name: String,
}


struct Query;

#[async_graphql::Object]
impl Query {
    /// 認証済みのユーザープロファイルを取得します。
    async fn me(&self, ctx: &async_graphql::Context<'_>) -> async_graphql::Result<UserProfile> {
        // TODO: JWTからユーザーIDを取得し、認可ロジックを追加
        let user_id = "test-user".to_string(); // 仮のユーザーID

        let user_service_client = ctx.data::<Arc<Mutex<UserServiceClient<Channel>>>>()?;
        let mut client = user_service_client.lock().await.clone();
        let request = tonic::Request::new(GetUserProfileRequest { user_id });
        let response = client.get_user_profile(request).await?.into_inner();

        let notification_settings: HashMap<String, String> = response
            .notification_settings
            .into_iter()
            .map(|(k, v)| (k, v))
            .collect();

        Ok(UserProfile {
            id: response.user_id,
            display_name: response.display_name,
            notification_settings,
        })
    }

    /// レポート一覧を取得します。
    async fn reports(&self, _ctx: &async_graphql::Context<'_>) -> Vec<Report> {
        // TODO: Report Serviceを呼び出し、認可ロジックを追加
        vec![
            Report {
                id: "1".to_string(),
                title: "Report 1".to_string(),
                content: "Content 1".to_string(),
                created_at: "2023-01-01".to_string(),
            },
            Report {
                id: "2".to_string(),
                title: "Report 2".to_string(),
                content: "Content 2".to_string(),
                created_at: "2023-01-02".to_string(),
            },
        ]
    }

    /// 特定のレポートを取得します。
    async fn report(&self, _ctx: &async_graphql::Context<'_>, id: String) -> Option<Report> {
        // TODO: Report Serviceを呼び出し、認可ロジックを追加
        Some(Report {
            id: id.clone(),
            title: format!("Report {}", id),
            content: format!("Content {}", id),
            created_at: "2023-01-01".to_string(),
        })
    }
}

struct Mutation;

#[async_graphql::Object]
impl Mutation {
    /// ユーザー認証を行い、JWTを返します。
    async fn login(
        &self,
        ctx: &async_graphql::Context<'_>,
        username: String,
        password: String,
    ) -> async_graphql::Result<LoginPayload> {
        let user_service_client = ctx.data::<Arc<Mutex<UserServiceClient<Channel>>>>()?;
        let mut client = user_service_client.lock().await.clone();
        let request = tonic::Request::new(LoginRequest { username, password });
        let response = client.login(request).await?.into_inner();

        Ok(LoginPayload {
            token: response.token,
            expires_in: response.expires_in as i32,
        })
    }

    /// ユーザープロファイルを更新します。
    async fn update_user_profile(
        &self,
        ctx: &async_graphql::Context<'_>,
        display_name: Option<String>,
        notification_settings: Option<Vec<NotificationSettingInput>>,
    ) -> async_graphql::Result<UserProfile> {
        // TODO: JWTからユーザーIDを取得し、認可ロジックを追加
        let user_id = "test-user".to_string(); // 仮のユーザーID

        let user_service_client = ctx.data::<Arc<Mutex<UserServiceClient<Channel>>>>()?;
        let mut client = user_service_client.lock().await.clone();
        let mut request = UpdateUserProfileRequest {
            user_id: user_id.clone(),
            display_name: display_name, // Option<String>のまま渡す
            notification_settings: HashMap::new(),
        };

        if let Some(settings) = notification_settings {
            for setting in settings {
                request.notification_settings.insert(setting.key, setting.value);
            }
        }

        client
            .update_user_profile(tonic::Request::new(request))
            .await?
            .into_inner();

        // 更新後のユーザープロファイルを取得して返す
        let query = Query;
        let updated_profile = query.me(ctx).await?;
        Ok(updated_profile)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, async_graphql::SimpleObject)]
struct UserProfile {
    id: String,
    display_name: String,
    notification_settings: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, async_graphql::InputObject)]
struct NotificationSettingInput {
    key: String,
    value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, async_graphql::SimpleObject)]
struct LoginPayload {
    token: String,
    expires_in: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, async_graphql::SimpleObject)]
struct Report {
    id: String,
    title: String,
    content: String,
    created_at: String,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    let user_service_url = std::env::var("USER_SERVICE_URL")
        .unwrap_or_else(|_| "http://localhost:50051".to_string());

    let channel = tonic::transport::Endpoint::from_shared(user_service_url)
        .expect("Invalid User Service URL")
        .connect()
        .await
        .expect("Failed to connect to User Service");
    let user_service_client = Arc::new(Mutex::new(UserServiceClient::new(channel)));

    let schema = Schema::build(Query, Mutation, EmptySubscription)
        .data(user_service_client.clone())
        .finish();

    let graphql_post = async_graphql_warp::graphql(schema).and_then(
        |(schema, request): (
            Schema<Query, Mutation, EmptySubscription>,
            async_graphql::Request,
        )| async move {
            Ok::<_, Infallible>(GraphQLResponse::from(schema.execute(request).await))
        },
    );

    let routes = warp::path("graphql").and(graphql_post);

    warp::serve(routes).run(([127, 0, 0, 1], 8000)).await;
}
