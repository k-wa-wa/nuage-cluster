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
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  # 非ローカルIPアドレスのバインドを許可する
  # ip_nonlocal_bind は VIP 運用のために入れた。VIP 廃止後も、各サービスが自ノード IP に bind する際に
  # IP の付与より先に起動しても失敗しないよう残す
  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
  };

  # keepalived (PostgreSQL の VIP) を撤去した後も、notify スクリプトが書いた状態ファイルがノードに残り、
  # node-exporter が古い keepalived_instance_state を出し続けるため削除する
  systemd.tmpfiles.rules = [
    "r /var/lib/prometheus/node-exporter/keepalived_VI_PG_PRIMARY.prom - - - - -"
    "r /var/lib/prometheus/node-exporter/keepalived_VI_PG_REPLICA.prom - - - - -"
  ];

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
