{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    ./swfs.nix
    ./keepalived.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  # 非ローカルIPアドレスのバインドを許可する（VIP運用のため）、およびIPv6を無効化する
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.ipv6.conf.all.disable_ipv6" = 1;
    "net.ipv6.conf.default.disable_ipv6" = 1;
  };

  services.prometheus.exporters.node = {
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus/node-exporter"
    ];
  };

  system.autoUpgrade.healthCheck.requiredUnits = [
    "swfs-master.service"
    "swfs-volume.service"
    "swfs-filer.service"
  ];
}
