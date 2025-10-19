use async_graphql::{Error, SimpleObject, InputObject};
use serde::{Deserialize, Serialize};
use reqwest;
use serde_json;
use chrono::{DateTime, Utc};
use std::env;

// Define custom scalars as aliases to existing types for GraphQL schema generation
type ISO8601DateTime = DateTime<Utc>;
pub type VapidPublicKey = String;

// PushNotification Type
#[derive(SimpleObject, Serialize, Deserialize)]
pub struct PushNotification {
    pub message: Option<String>,
    pub success: bool,
}

// SubscriptionKeysInput Input
#[derive(InputObject, Serialize, Deserialize)]
pub struct SubscriptionKeysInput {
    pub auth: String,
    pub p256dh: String,
}

// SubscriptionInput Input
#[derive(InputObject, Serialize, Deserialize)]
pub struct SubscriptionInput {
    pub endpoint: String,
    #[graphql(name = "expirationTime")]
    pub expiration_time: Option<ISO8601DateTime>,
    pub keys: SubscriptionKeysInput,
}

pub async fn get_vapid_public_key() -> Result<VapidPublicKey, Error> {
    let micro_gopush_url = env::var("MICRO_GOPUSH_URL").expect("MICRO_GOPUSH_URL not found: {}");
    let client = reqwest::Client::new();

    let res = client.get(format!("{}/vapid-public-key", micro_gopush_url))
        .send()
        .await
        .map_err(|e| Error::new(format!("Failed to fetch VAPID public key: {}", e)))?;

    let vapid_public_key_str = res.text().await
        .map_err(|e| Error::new(format!("Failed to parse VAPID public key response: {}", e)))?;

    Ok(vapid_public_key_str)
}

pub async fn notify_all_clients(message: Option<String>) -> Result<PushNotification, Error> {
    let micro_gopush_url = env::var("MICRO_GOPUSH_URL").expect("MICRO_GOPUSH_URL not found: {}");
    let client = reqwest::Client::new();
    let msg = message.unwrap_or_else(|| "".to_string());

    let res = client.post(format!("{}/notify-all", micro_gopush_url))
        .json(&serde_json::json!({ "message": msg }))
        .send()
        .await
        .map_err(|e| Error::new(format!("Failed to send notifyAll request: {}", e)))?;

    let push_notification: PushNotification = res.json().await
        .map_err(|e| Error::new(format!("Failed to parse notifyAll response: {}", e)))?;

    Ok(push_notification)
}

pub async fn subscribe_client(subscription: SubscriptionInput) -> Result<PushNotification, Error> {
    let micro_gopush_url = env::var("MICRO_GOPUSH_URL").expect("MICRO_GOPUSH_URL not found: {}");
    let client = reqwest::Client::new();

    let res = client.post(format!("{}/subscribe", micro_gopush_url))
        .json(&subscription)
        .send()
        .await
        .map_err(|e| Error::new(format!("Failed to send subscribe request: {}", e)))?;

    let push_notification: PushNotification = res.json().await
        .map_err(|e| Error::new(format!("Failed to parse subscribe response: {}", e)))?;

    Ok(push_notification)
}
