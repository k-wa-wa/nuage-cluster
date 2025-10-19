use kube::{Api, Client, Config};
use kube::config::Kubeconfig;
use async_graphql::Error;

use crate::crd::{ApplicationList, ApplicationListSpec};

pub async fn initialize_kube_client() -> Result<Client, Error> {
    if let Ok(kube_config_path) = std::env::var("KUBE_CONFIG") {
        println!("Using KUBE_CONFIG from: {}", kube_config_path);
        let kube_config = Kubeconfig::read_from(&kube_config_path)
            .map_err(|e| Error::new(format!("Failed to read KUBE_CONFIG: {}", e)))?;
        let config = Config::from_custom_kubeconfig(kube_config, &Default::default())
            .await
            .map_err(|e| Error::new(format!("Failed to create Kube client from KUBE_CONFIG: {}", e)))?;
        Client::try_from(config)
            .map_err(|e| Error::new(format!("Failed to create Kube client from KUBE_CONFIG: {}", e)))
    } else {
        println!("KUBE_CONFIG not set, attempting in-cluster configuration.");
        Client::try_default()
            .await
            .map_err(|e| Error::new(format!("Failed to create in-cluster Kube client: {}", e)))
    }
}

pub async fn get_application_list_spec(client: &Client, name: String) -> Result<ApplicationListSpec, Error> {
    let api: Api<ApplicationList> = Api::namespaced(client.clone(), "nuage-monitoring");
    let application_lists = api.get(&name).await
        .map_err(|e| Error::new(format!("Failed to list ApplicationLists: {}", e)))?;
    Ok(application_lists.spec)
}
