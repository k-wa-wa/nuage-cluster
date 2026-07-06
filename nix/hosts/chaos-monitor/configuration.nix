{ pkgs, ... }:

{
  imports = [
    ../base-lxc/configuration.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  # Prometheus Configuration
  services.prometheus = {
    enable = true;
    port = 9090;
    scrapeConfigs = [
      {
        job_name = "talos-nodes";
        scrape_interval = "5s";
        static_configs = [{
          targets = [
            "10.20.1.11:10250"
            "10.20.1.12:10250"
            "10.20.1.13:10250"
            "10.20.1.16:10250"
            "10.20.1.17:10250"
            "10.20.1.18:10250"
          ];
        }];
      }
      {
        job_name = "nixos-node-exporter";
        scrape_interval = "5s";
        static_configs = [{
          targets = [
            "10.20.1.21:9100"
            "10.20.1.22:9100"
            "10.20.1.23:9100"
            "10.20.1.30:9100"
          ];
        }];
      }
      {
        job_name = "nixos-haproxy";
        scrape_interval = "5s";
        static_configs = [{
          targets = [
            "10.20.1.21:8404"
            "10.20.1.22:8404"
            "10.20.1.23:8404"
            "10.20.1.30:8404"
          ];
        }];
      }
    ];
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
