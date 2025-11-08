use async_graphql::{EmptySubscription, Schema};
use async_graphql_warp::GraphQLResponse;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::convert::Infallible;
use tonic::transport::Channel;
use warp::{Filter, http::Method};
use std::sync::Arc;
use tokio::sync::Mutex;

mod proto {
    pub mod user_service {
        tonic::include_proto!("user_service");
    }
    pub mod report_service {
        tonic::include_proto!("report_service");
    }
}

use proto::user_service::{
    user_service_client::UserServiceClient, GetUserProfileRequest, LoginRequest,
    UpdateUserProfileRequest,
};
use proto::report_service::{
    report_service_client::ReportServiceClient, GetReportRequest, ListReportsRequest,
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
    async fn reports(
        &self,
        ctx: &async_graphql::Context<'_>,
        user_id: String, // TODO: JWTからユーザーIDを取得
        page_size: Option<i32>,
        page_token: Option<String>,
    ) -> async_graphql::Result<Vec<Report>> {
        // TODO: 認可ロジックを追加
        let report_service_client = ctx.data::<Arc<Mutex<ReportServiceClient<Channel>>>>()?;
        let mut client = report_service_client.lock().await.clone();
        let request = tonic::Request::new(ListReportsRequest {
            user_id,
            page_size: page_size.unwrap_or(10),
            page_token: page_token.unwrap_or_default(),
        });
        let response = client.list_reports(request).await?.into_inner();

        let reports: Vec<Report> = response
            .reports
            .into_iter()
            .map(|r| Report {
                report_id: r.report_id,
                report_body: r.report_body,
                user_id: r.user_id,
                created_at_unix: r.created_at_unix,
            })
            .collect();

        Ok(reports)
    }

    /// 特定のレポートを取得します。
    async fn report(&self, ctx: &async_graphql::Context<'_>, report_id: String) -> async_graphql::Result<Option<Report>> {
        // TODO: 認可ロジックを追加
        let report_service_client = ctx.data::<Arc<Mutex<ReportServiceClient<Channel>>>>()?;
        let mut client = report_service_client.lock().await.clone();
        let request = tonic::Request::new(GetReportRequest { report_id: report_id.clone() });
        let response = client.get_report(request).await?.into_inner();

        if let Some(r) = response.report {
            Ok(Some(Report {
                report_id: r.report_id,
                report_body: r.report_body,
                user_id: r.user_id,
                created_at_unix: r.created_at_unix,
            }))
        } else {
            Ok(None)
        }
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
    report_id: String,
    report_body: String,
    user_id: String,
    created_at_unix: i64,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();

    // スキーマをファイルに書き出す (開発用)
    // サービス接続の前にスキーマを生成
    let schema_for_sdl = Schema::build(Query, Mutation, EmptySubscription).finish();
    let schema_sdl = schema_for_sdl.sdl();
    //std::fs::write("../ui/schema.graphql", schema_sdl).expect("Failed to write schema");
    //println!("GraphQL schema written to ../ui/schema.graphql"); // スキーマ出力の確認メッセージを追加

    let user_service_url = std::env::var("USER_SERVICE_URL")
        .unwrap_or_else(|_| "http://localhost:50051".to_string());
    let report_service_url = std::env::var("REPORT_SERVICE_URL")
        .unwrap_or_else(|_| "http://localhost:50052".to_string());

    let user_service_client_arc: Option<Arc<Mutex<UserServiceClient<Channel>>>>;
    let report_service_client_arc: Option<Arc<Mutex<ReportServiceClient<Channel>>>>;

    // User Serviceへの接続を試みる
    match tonic::transport::Endpoint::from_shared(user_service_url.clone()) {
        Ok(endpoint) => {
            match endpoint.connect().await {
                Ok(channel) => {
                    user_service_client_arc = Some(Arc::new(Mutex::new(UserServiceClient::new(channel))));
                    println!("Connected to User Service at {}", user_service_url);
                },
                Err(e) => {
                    eprintln!("Failed to connect to User Service at {}: {}", user_service_url, e);
                    user_service_client_arc = None;
                }
            }
        },
        Err(e) => {
            eprintln!("Invalid User Service URL {}: {}", user_service_url, e);
            user_service_client_arc = None;
        }
    }

    // Report Serviceへの接続を試みる
    match tonic::transport::Endpoint::from_shared(report_service_url.clone()) {
        Ok(endpoint) => {
            match endpoint.connect().await {
                Ok(channel) => {
                    report_service_client_arc = Some(Arc::new(Mutex::new(ReportServiceClient::new(channel))));
                    println!("Connected to Report Service at {}", report_service_url);
                },
                Err(e) => {
                    eprintln!("Failed to connect to Report Service at {}: {}", report_service_url, e);
                    report_service_client_arc = None;
                }
            }
        }
        Err(e) => {
            eprintln!("Invalid Report Service URL {}: {}", report_service_url, e);
            report_service_client_arc = None;
        }
    }

    let mut schema_builder = Schema::build(Query, Mutation, EmptySubscription);

    if let Some(client) = user_service_client_arc {
        schema_builder = schema_builder.data(client);
    } else {
        eprintln!("User Service client not available. Some GraphQL queries/mutations may fail.");
    }

    if let Some(client) = report_service_client_arc {
        schema_builder = schema_builder.data(client);
    } else {
        eprintln!("Report Service client not available. Some GraphQL queries/mutations may fail.");
    }

    let schema = schema_builder.finish();

    let graphql_post = async_graphql_warp::graphql(schema).and_then(
        |(schema, request): (
            Schema<Query, Mutation, EmptySubscription>,
            async_graphql::Request,
        )| async move {
            Ok::<_, Infallible>(GraphQLResponse::from(schema.execute(request).await))
        },
    );

    let cors = warp::cors()
        .allow_any_origin()
        .allow_headers(vec!["User-Agent", "Sec-Fetch-Mode", "Referer", "Origin", "Access-Control-Request-Method", "Access-Control-Request-Headers", "Content-Type"])
        .allow_methods(&[Method::GET, Method::POST, Method::PUT, Method::DELETE, Method::OPTIONS]);

    let routes = warp::path("graphql").and(graphql_post).with(cors);

    warp::serve(routes).run(([127, 0, 0, 1], 8000)).await;
}
