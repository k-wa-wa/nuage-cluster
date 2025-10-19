use actix_web::{web, App, HttpServer, HttpResponse, Result, guard};
use async_graphql::{EmptySubscription, Schema, Object, Context, SimpleObject, InputObject};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse};
use async_graphql::http::{playground_source, GraphQLPlaygroundConfig};
use dotenvy::dotenv;
use std::env;
use std::ptr::null;
use sqlx::{PgPool, FromRow};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use reqwest;
use serde_json; // Keep this for the json! macro
use kube::{Api, Client, Config};
use kube::config::Kubeconfig; // Import Kubeconfig

mod crd;
use crd::{ApplicationList, Application};

use crate::crd::ApplicationListSpec;

// Define your GraphQL Query
struct Query;
struct Mutation;

// Helper function to convert camelCase to snake_case
fn camel_to_snake_case(s: &str) -> String {
    let mut snake_case = String::new();
    for (i, char) in s.chars().enumerate() {
        if char.is_ascii_uppercase() {
            if i > 0 {
                snake_case.push('_');
            }
            snake_case.push(char.to_ascii_lowercase());
        } else {
            snake_case.push(char);
        }
    }
    snake_case
}

// Define custom scalars as aliases to existing types for GraphQL schema generation
type ISO8601DateTime = DateTime<Utc>;
type VapidPublicKey = String;

// PushNotification Type
#[derive(SimpleObject, Serialize, Deserialize)]
struct PushNotification {
    message: Option<String>,
    success: bool,
}

// SubscriptionKeysInput Input
#[derive(InputObject, Serialize, Deserialize)]
struct SubscriptionKeysInput {
    auth: String,
    p256dh: String,
}

// SubscriptionInput Input
#[derive(InputObject, Serialize, Deserialize)]
struct SubscriptionInput {
    endpoint: String,
    #[graphql(name = "expirationTime")]
    expiration_time: Option<ISO8601DateTime>,
    keys: SubscriptionKeysInput,
}

// Define the Report struct matching the database schema
#[derive(FromRow, SimpleObject)]
struct Report {
    #[graphql(skip)] // Do not expose seq_id in GraphQL schema
    seq_id: i32,
    report_id: Uuid,
    report_name: String,
    report_type: String,
    generated_at: ISO8601DateTime, // This remains snake_case to match DB
    content: String,
    status: String,
}

#[Object]
impl Query {
    async fn hello(&self, _ctx: &Context<'_>) -> String {
        "Hello, GraphQL!".to_string()
    }

    async fn application_list(&self, ctx: &Context<'_>, name: String) -> Result<ApplicationListSpec, async_graphql::Error> {
        let client = ctx.data::<Client>().expect("Kube client not found in context");
        let api: Api<ApplicationList> = Api::namespaced(client.clone(), "nuage-monitoring");

        let application_lists = api.get(&name).await
            .map_err(|e| async_graphql::Error::new(format!("Failed to list ApplicationLists: {}", e)))?;

        Ok(application_lists.spec)
    }

    async fn reports(&self, ctx: &Context<'_>, sort: Option<String>) -> Result<Vec<Report>, async_graphql::Error> {
        let pool = ctx.data::<PgPool>().expect("PgPool not found in context");

        let mut query_string = "SELECT * FROM reports".to_string();
        if let Some(sort_str) = sort {
            let parts: Vec<&str> = sort_str.split(':').collect();
            if parts.len() == 2 {
                let column = parts[0];
                let order = parts[1].to_uppercase(); // ASC or DESC

                // Basic sanitization: only allow known columns and orders
                let allowed_columns = ["reportName", "reportType", "generatedAt", "status"];
                if allowed_columns.contains(&column) && (order == "ASC" || order == "DESC") {
                    let db_column = camel_to_snake_case(column);
                    query_string.push_str(&format!(" ORDER BY \"{}\" {}", db_column, order));
                } else {
                    return Err(async_graphql::Error::new("Invalid sort column or order."));
                }
            } else {
                return Err(async_graphql::Error::new("Invalid sort format. Expected 'column:order'."));
            }
        }

        let reports = sqlx::query_as::<_, Report>(&query_string)
            .fetch_all(pool)
            .await
            .map_err(|e| async_graphql::Error::new(e.to_string()))?;
        Ok(reports)
    }

    /// A temporary response from the gateway server
    async fn temporary_response(&self) -> String {
        "This is a temporary response from the gateway.".to_string()
    }

    /// The VAPID public key for WebPush notifications
    async fn vapid_public_key(&self, _ctx: &Context<'_>) -> Result<VapidPublicKey, async_graphql::Error> {
        let micro_gopush_url = env::var("MICRO_GOPUSH_URL").expect("MICRO_GOPUSH_URL not found: {}");
        let client = reqwest::Client::new();

        let res = client.get(format!("{}/vapid-public-key", micro_gopush_url))
            .send()
            .await
            .map_err(|e| async_graphql::Error::new(format!("Failed to fetch VAPID public key: {}", e)))?;

        let vapid_public_key_str = res.text().await
            .map_err(|e| async_graphql::Error::new(format!("Failed to parse VAPID public key response: {}", e)))?;

        Ok(vapid_public_key_str)
    }
}

#[Object]
impl Mutation {
    /// Sends a push notification to all subscribed clients
    async fn notify_all(&self, _ctx: &Context<'_>, message: Option<String>) -> Result<PushNotification, async_graphql::Error> {
        let micro_gopush_url = env::var("MICRO_GOPUSH_URL").expect("MICRO_GOPUSH_URL not found: {}");
        let client = reqwest::Client::new();
        let msg = message.unwrap_or_else(|| "".to_string());

        let res = client.post(format!("{}/notify-all", micro_gopush_url))
            .json(&serde_json::json!({ "message": msg }))
            .send()
            .await
            .map_err(|e| async_graphql::Error::new(format!("Failed to send notifyAll request: {}", e)))?;

        let push_notification: PushNotification = res.json().await
            .map_err(|e| async_graphql::Error::new(format!("Failed to parse notifyAll response: {}", e)))?;

        Ok(push_notification)
    }

    /// Subscribes a client to WebPush notifications
    async fn subscribe(&self, _ctx: &Context<'_>, subscription: SubscriptionInput) -> Result<PushNotification, async_graphql::Error> {
        let micro_gopush_url = env::var("MICRO_GOPUSH_URL").expect("MICRO_GOPUSH_URL not found: {}");
        let client = reqwest::Client::new();

        let res = client.post(format!("{}/subscribe", micro_gopush_url))
            .json(&subscription)
            .send()
            .await
            .map_err(|e| async_graphql::Error::new(format!("Failed to send subscribe request: {}", e)))?;

        let push_notification: PushNotification = res.json().await
            .map_err(|e| async_graphql::Error::new(format!("Failed to parse subscribe response: {}", e)))?;

        Ok(push_notification)
    }

    /// An example field added by the generator
    async fn test_field(&self) -> String {
        "This is a test field from Mutation!".to_string()
    }
}

// Create the GraphQL Schema
type AppSchema = Schema<Query, Mutation, EmptySubscription>;

// GraphQL endpoint handler
async fn index(schema: web::Data<AppSchema>, req: GraphQLRequest) -> GraphQLResponse {
    schema.execute(req.into_inner()).await.into()
}

// GraphiQL playground handler
async fn index_playground() -> HttpResponse {
    HttpResponse::Ok()
        .content_type("text/html; charset=utf-8")
        .body(playground_source(
            GraphQLPlaygroundConfig::new("/graphql")
        ))
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    dotenv().ok();

    let db_host = env::var("DB_HOST").expect("DB_HOST must be set");
    let db_port = env::var("DB_PORT").expect("DB_PORT must be set");
    let db_user = env::var("DB_USER").expect("DB_USER must be set");
    let db_password = env::var("DB_PASSWORD").expect("DB_PASSWORD must be set");
    let db_name = env::var("DB_NAME").expect("DB_NAME must be set");

    let database_url = format!(
        "postgres://{}:{}@{}:{}/{}",
        db_user, db_password, db_host, db_port, db_name
    );
    let server_address = format!("0.0.0.0:3000");

    // Establish PostgreSQL connection pool
    let pool = PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to Postgres");

    // Initialize Kubernetes client
    let kube_client = if let Ok(kube_config_path) = env::var("KUBE_CONFIG") {
        println!("Using KUBE_CONFIG from: {}", kube_config_path);
        let kube_config = Kubeconfig::read_from(&kube_config_path)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, format!("Failed to read KUBE_CONFIG: {}", e)))?;
        let config = Config::from_custom_kubeconfig(kube_config, &Default::default())
            .await
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, format!("Failed to create Kube client from KUBE_CONFIG: {}", e)))?;
        Client::try_from(config)
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, format!("Failed to create Kube client from KUBE_CONFIG: {}", e)))?
    } else {
        println!("KUBE_CONFIG not set, attempting in-cluster configuration.");
        Client::try_default()
            .await
            .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, format!("Failed to create in-cluster Kube client: {}", e)))?
    };

    let schema = Schema::build(Query, Mutation, EmptySubscription)
        .data(pool.clone()) // Add the connection pool to the GraphQL context
        .data(kube_client.clone()) // Add the Kubernetes client to the GraphQL context
        .finish();

    println!("GraphiQL playground: http://{}", server_address);
    println!("GraphQL endpoint: http://{}/graphql", server_address);

    // Output GraphQL Schema to a file
    let schema_sdl = schema.sdl();
    std::fs::write("schema.graphql", schema_sdl)
        .expect("Failed to write schema.graphql");
    println!("GraphQL schema written to schema.graphql");

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(schema.clone()))
            .service(web::resource("/graphql").guard(guard::Post()).to(index))
            .service(web::resource("/").guard(guard::Get()).to(index_playground))
    })
    .bind(&server_address)?
    .run()
    .await
}
