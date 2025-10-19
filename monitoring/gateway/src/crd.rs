use kube::CustomResource;
use serde::{Deserialize, Serialize};
use async_graphql::SimpleObject;
use schemars::JsonSchema;

// ApplicationLink defines a link for an application.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, SimpleObject, JsonSchema)]
pub struct ApplicationLink {
    #[serde(rename = "buttonName")]
    pub button_name: String,
    #[serde(rename = "iconName")]
    pub icon_name: Option<String>,
    #[serde(rename = "linkUrls")]
    pub link_urls: LinkUrls,
}

// LinkUrls defines URLs for different platforms.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, SimpleObject, JsonSchema)]
pub struct LinkUrls {
    pub web: Option<String>,
    pub ios: Option<String>,
}

// IconUrls defines URLs for different icon sizes.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, SimpleObject, JsonSchema)]
pub struct IconUrls {
    pub small: Option<String>,
    pub medium: Option<String>,
    pub large: Option<String>,
}

// Application defines the structure of an individual application.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, SimpleObject, JsonSchema)]
pub struct Application {
    pub name: String,
    pub description: Option<String>,
    pub category: Option<String>,
    #[serde(rename = "iconUrls")]
    pub icon_urls: Option<IconUrls>,
    #[serde(rename = "launchUrls")]
    pub launch_urls: Option<LinkUrls>, // Re-using LinkUrls for launch URLs
    #[serde(rename = "additionalLinks")]
    pub additional_links: Option<Vec<ApplicationLink>>,
}

// ApplicationListSpec defines the desired state of ApplicationList.
#[derive(CustomResource, Debug, Clone, PartialEq, Serialize, Deserialize, SimpleObject, JsonSchema)]
#[kube(group = "example.com", version = "v1alpha1", kind = "ApplicationList", plural = "applicationlists")]
#[kube(namespaced)]
pub struct ApplicationListSpec {
    pub applications: Vec<Application>,
}
