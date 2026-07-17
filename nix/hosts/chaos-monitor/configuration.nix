{ pkgs, ... }:

{
  imports = [
    ../base-lxc/configuration.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
    hosts = {
      "192.168.5.200" = [
        "pechka.cluster.wpc"
        "pechka-workflow.cluster.wpc"
        "argocd.cluster.wpc"
        "bwproxy.cluster.wpc"
      ];
    };
  };

  # Prometheus Configuration
  services.prometheus = {
    enable = true;
    port = 9090;
    scrapeConfigs = [
      {
        job_name = "nixos-node-exporter";
        scrape_interval = "5s";
        static_configs = [
          { targets = [ "10.20.1.21:9100" ]; labels = { node = "lb-1"; }; }
          { targets = [ "10.20.1.22:9100" ]; labels = { node = "lb-2"; }; }
          { targets = [ "10.20.1.23:9100" ]; labels = { node = "lb-3"; }; }
          { targets = [ "10.20.1.30:9100" ]; labels = { node = "egress-gateway"; }; }
          { targets = [ "10.20.1.41:9100" ]; labels = { node = "pg-cluster-1"; }; }
          { targets = [ "10.20.1.42:9100" ]; labels = { node = "pg-cluster-2"; }; }
          { targets = [ "10.20.1.43:9100" ]; labels = { node = "pg-cluster-3"; }; }
          { targets = [ "10.20.1.71:9100" ]; labels = { node = "minio-cluster-1"; }; }
          { targets = [ "10.20.1.72:9100" ]; labels = { node = "minio-cluster-2"; }; }
        ];
      }
      {
        job_name = "nixos-haproxy";
        scrape_interval = "5s";
        static_configs = [
          { targets = [ "10.20.1.21:8404" ]; labels = { node = "lb-1"; }; }
          { targets = [ "10.20.1.22:8404" ]; labels = { node = "lb-2"; }; }
          { targets = [ "10.20.1.23:8404" ]; labels = { node = "lb-3"; }; }
          { targets = [ "10.20.1.30:8404" ]; labels = { node = "egress-gateway"; }; }
        ];
      }
      {
        job_name = "node-ping";
        metrics_path = "/probe";
        params = {
          module = [ "icmp" ];
        };
        static_configs = [
          { targets = [ "10.20.1.11" ]; labels = { node = "controlplane-01"; }; }
          { targets = [ "10.20.1.12" ]; labels = { node = "controlplane-02"; }; }
          { targets = [ "10.20.1.13" ]; labels = { node = "controlplane-03"; }; }
          { targets = [ "10.20.1.16" ]; labels = { node = "worker-01"; }; }
          { targets = [ "10.20.1.17" ]; labels = { node = "worker-02"; }; }
          { targets = [ "10.20.1.18" ]; labels = { node = "worker-03"; }; }
          { targets = [ "10.20.1.21" ]; labels = { node = "lb-1"; }; }
          { targets = [ "10.20.1.22" ]; labels = { node = "lb-2"; }; }
          { targets = [ "10.20.1.23" ]; labels = { node = "lb-3"; }; }
          { targets = [ "10.20.1.30" ]; labels = { node = "egress-gateway"; }; }
          { targets = [ "10.20.1.41" ]; labels = { node = "pg-cluster-1"; }; }
          { targets = [ "10.20.1.42" ]; labels = { node = "pg-cluster-2"; }; }
          { targets = [ "10.20.1.43" ]; labels = { node = "pg-cluster-3"; }; }
          { targets = [ "10.20.1.40" ]; labels = { node = "pg-cluster-vip"; }; }
          { targets = [ "10.20.1.71" ]; labels = { node = "minio-cluster-1"; }; }
          { targets = [ "10.20.1.72" ]; labels = { node = "minio-cluster-2"; }; }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
      }
      {
        job_name = "http-ingress-probe";
        scrape_interval = "5s";
        metrics_path = "/probe";
        params = {
          module = [ "http_insecure" ];
        };
        static_configs = [
          {
            targets = [ "https://pechka.cluster.wpc/" ];
            labels = { service = "pechka"; };
          }
          {
            targets = [ "https://pechka-workflow.cluster.wpc/" ];
            labels = { service = "pechka-workflow"; };
          }
          {
            targets = [ "https://argocd.cluster.wpc/" ];
            labels = { service = "argocd"; };
          }
          {
            targets = [ "https://bwproxy.cluster.wpc/" ];
            labels = { service = "bare-web-proxy"; };
          }
          {
            targets = [ "http://10.20.1.70:9000/minio/health/live" ];
            labels = { service = "minio"; };
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
      }
      {
        job_name = "tcp-port-probe";
        scrape_interval = "5s";
        metrics_path = "/probe";
        params = {
          module = [ "tcp_connect" ];
        };
        static_configs = [
          {
            targets = [ "10.20.1.40:5432" ];
            labels = { service = "postgres"; };
          }
        ];
        relabel_configs = [
          {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          }
          {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          }
          {
            target_label = "__address__";
            replacement = "127.0.0.1:9115";
          }
        ];
      }
    ];

    exporters.blackbox = {
      enable = true;
      port = 9115;
      configFile = ./blackbox.yaml;
    };
  };

  # Grafana Configuration
  services.grafana = {
    enable = true;
    settings.server = {
      http_addr = "0.0.0.0";
      http_port = 3000;
    };
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:9090";
          access = "proxy";
          isDefault = true;
        }
      ];
      dashboards.settings.providers = [
        {
          name = "Chaos Dashboards";
          options.path = "/var/lib/grafana/dashboards";
        }
      ];
    };
  };

  # Declaratively symlink the dashboard JSON into Grafana dashboards directory
  systemd.tmpfiles.rules = [
    "d /var/lib/grafana/dashboards 0755 grafana grafana -"
    "L+ /var/lib/grafana/dashboards/chaos-dashboard.json - - - - ${./chaos-dashboard.json}"
  ];

  networking.firewall.allowedTCPPorts = [
    3000
  ];
}
