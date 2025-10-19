use sqlx::{PgPool, FromRow};
use uuid::Uuid;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use async_graphql::{SimpleObject, Error};

// Define custom scalars as aliases to existing types for GraphQL schema generation
type ISO8601DateTime = DateTime<Utc>;

// Define the Report struct matching the database schema
#[derive(FromRow, SimpleObject, Serialize, Deserialize)]
pub struct Report {
    #[graphql(skip)] // Do not expose seq_id in GraphQL schema
    pub seq_id: i32,
    pub report_id: Uuid,
    pub report_name: String,
    pub report_type: String,
    pub generated_at: ISO8601DateTime, // This remains snake_case to match DB
    pub content: String,
    pub status: String,
}

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

pub async fn establish_connection_pool(database_url: &str) -> Result<PgPool, Error> {
    PgPool::connect(database_url)
        .await
        .map_err(|e| Error::new(format!("Failed to connect to Postgres: {}", e)))
}

pub async fn get_reports(pool: &PgPool, sort: Option<String>) -> Result<Vec<Report>, Error> {
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
                return Err(Error::new("Invalid sort column or order."));
            }
        } else {
            return Err(Error::new("Invalid sort format. Expected 'column:order'."));
        }
    }

    sqlx::query_as::<_, Report>(&query_string)
        .fetch_all(pool)
        .await
        .map_err(|e| Error::new(e.to_string()))
}
