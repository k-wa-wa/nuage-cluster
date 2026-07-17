{ pkgs, lib, config, ... }:

{
  imports = [
    ./minio.nix
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

  # 各ノードのメトリクス収集用ノードエクスポーターを有効化する
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus/node-exporter"
    ];
  };

  # メトリクス収集用ポートを開放する
  networking.firewall.allowedTCPPorts = [ 9100 ];
}
