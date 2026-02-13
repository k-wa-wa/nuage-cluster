provider "helm" {
  kubernetes = {
    host                   = "${[for k, v in var.cluster_config.nodes : v.management_ip_address if v.type == "controlplane"][0]}:6443"
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  }
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  namespace  = "kube-system"

  set = [
    {
      name  = "bgpControlPlane.enabled"
      value = "false"
    },
    {
      name  = "l2announcements.enabled"
      value = "true"
    },
    {
      name  = "externalIPs.enabled"
      value = "true"
    },
    {
      name  = "devices",
      value = "{ens18}"
    },
    {
      name  = "extraArgs"
      value = "{--direct-routing-device=ens18}"
    },
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "k8sServiceHost"
      value = var.cluster_config.cluster.endpoint
    },
    {
      name  = "k8sServicePort"
      value = "6443"
    },
    {
      name  = "hubble.enabled"
      value = "true"
    },
    {
      name  = "hubble.ui.enabled"
      value = "true"
    },
    {
      name  = "hubble.relay.enabled"
      value = "true"
    },
    {
      name  = "securityContext.capabilities.ciliumAgent"
      value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}"
    },
    {
      name  = "securityContext.capabilities.cleanCiliumState"
      value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}"
    },
    {
      name  = "cgroup.autoMount.enabled"
      value = "true"
    },
    {
      name  = "cgroup.hostRoot"
      value = "/sys/fs/cgroup"
    }
  ]
}
