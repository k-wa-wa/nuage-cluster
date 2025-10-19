use actix_web::{web, App, HttpServer, HttpResponse, Result, guard};
use async_graphql::{EmptySubscription, Schema, Object, Context};
use actix_cors::Cors;
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse};
use async_graphql::http::{playground_source, GraphQLPlaygroundConfig};
use dotenvy::dotenv;
use std::env;
use sqlx::PgPool;

mod crd;
mod db;
mod k8s;
mod micro_gopush;

use crate::crd::ApplicationListSpec;
use crate::db::Report;
use crate::micro_gopush::{PushNotification, SubscriptionInput, VapidPublicKey};

// Define your GraphQL Query
struct Query;
struct Mutation;

#[Object]
impl Query {
    async fn hello(&self, _ctx: &Context<'_>) -> String {
        "Hello, GraphQL!".to_string()
    }

    async fn application_list(&self, ctx: &Context<'_>, name: String) -> Result<ApplicationListSpec, async_graphql::Error> {
        let client = ctx.data::<kube::Client>().expect("Kube client not found in context");
        k8s::get_application_list_spec(client, name).await
    }

    async fn reports(&self, ctx: &Context<'_>, sort: Option<String>) -> Result<Vec<Report>, async_graphql::Error> {
        let pool = ctx.data::<PgPool>().expect("PgPool not found in context");
        db::get_reports(pool, sort).await
    }

    /// A temporary response from the gateway server
    async fn temporary_response(&self) -> String {
        "This is a temporary response from the gateway.".to_string()
    }

    /// The VAPID public key for WebPush notifications
    async fn vapid_public_key(&self, _ctx: &Context<'_>) -> Result<VapidPublicKey, async_graphql::Error> {
        micro_gopush::get_vapid_public_key().await
    }
}

#[Object]
impl Mutation {
    /// Sends a push notification to all subscribed clients
    async fn notify_all(&self, _ctx: &Context<'_>, message: Option<String>) -> Result<PushNotification, async_graphql::Error> {
        micro_gopush::notify_all_clients(message).await
    }

    /// Subscribes a client to WebPush notifications
    async fn subscribe(&self, _ctx: &Context<'_>, subscription: SubscriptionInput) -> Result<PushNotification, async_graphql::Error> {
        micro_gopush::subscribe_client(subscription).await
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
    let pool = db::establish_connection_pool(&database_url)
        .await
        .expect("Failed to connect to Postgres");

    // Initialize Kubernetes client
    let kube_client = k8s::initialize_kube_client()
        .await
        .expect("Failed to initialize Kubernetes client");

    let schema = Schema::build(Query, Mutation, EmptySubscription)
        .data(pool.clone()) // Add the connection pool to the GraphQL context
        .data(kube_client.clone()) // Add the Kubernetes client to the GraphQL context
        .finish();

    println!("GraphQL playground: http://{}", server_address);
    println!("GraphQL endpoint: http://{}/graphql", server_address);

    // Output GraphQL Schema to a file
    let schema_sdl = schema.sdl();
    std::fs::write("schema.graphql", schema_sdl)
        .expect("Failed to write schema.graphql");
    println!("GraphQL schema written to schema.graphql");

    HttpServer::new(move || {
        let cors = Cors::permissive();

        App::new()
            .wrap(cors)
            .app_data(web::Data::new(schema.clone()))
            .service(web::resource("/graphql").guard(guard::Post()).to(index))
            .service(web::resource("/").guard(guard::Get()).to(index_playground))
    })
    .bind(&server_address)?
    .run()
    .await
}
