use actix_web::{web, App, HttpServer, HttpResponse, Result, guard};
use async_graphql::{EmptyMutation, EmptySubscription, Schema, Object, Context, SimpleObject};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse};
use async_graphql::http::{playground_source, GraphQLPlaygroundConfig};
use dotenvy::dotenv;
use std::env;
use sqlx::{PgPool, FromRow};
use uuid::Uuid;
use chrono::{DateTime, Utc};

// Define your GraphQL Query
struct Query;

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

// Define the Report struct matching the database schema
#[derive(FromRow, SimpleObject)]
struct Report {
    #[graphql(skip)] // Do not expose seq_id in GraphQL schema
    seq_id: i32,
    report_id: Uuid,
    report_name: String,
    report_type: String,
    generated_at: DateTime<Utc>, // This remains snake_case to match DB
    content: String,
    status: String,
}

#[Object]
impl Query {
    async fn hello(&self, _ctx: &Context<'_>) -> String {
        "Hello, GraphQL!".to_string()
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
}

// Create the GraphQL Schema
type AppSchema = Schema<Query, EmptyMutation, EmptySubscription>;

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

    let db_host = env::var("DB_HOST").unwrap_or_else(|_| "localhost".to_string());
    let db_port = env::var("DB_PORT").unwrap_or_else(|_| "5432".to_string());
    let db_user = env::var("DB_USER").expect("DB_USER must be set");
    let db_password = env::var("DB_PASSWORD").expect("DB_PASSWORD must be set");
    let db_name = env::var("DB_NAME").expect("DB_NAME must be set");

    let database_url = format!(
        "postgres://{}:{}@{}:{}/{}",
        db_user, db_password, db_host, db_port, db_name
    );
    let host = env::var("HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let server_address = format!("{}:{}", host, port);

    // Establish PostgreSQL connection pool
    let pool = PgPool::connect(&database_url)
        .await
        .expect("Failed to connect to Postgres");

    let schema = Schema::build(Query, EmptyMutation, EmptySubscription)
        .data(pool.clone()) // Add the connection pool to the GraphQL context
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
