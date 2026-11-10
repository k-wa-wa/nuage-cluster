{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    ./etcd.nix
    ./patroni.nix
    ./haproxy.nix
    ./keepalived.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  # 非ローカルIPアドレスのバインドを許可する（VIP運用のため）
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
  };

  services.prometheus.exporters.node = {
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus/node-exporter"
    ];
  };

  system.autoUpgrade.healthCheck.requiredUnits = [
    "patroni.service"
    "etcd.service"
  ];
}
