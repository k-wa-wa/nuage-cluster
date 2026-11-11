{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    ./swfs.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  # 非ローカルIPアドレスのバインドを許可する、およびIPv6を無効化する
  # ip_nonlocal_bind は VIP 運用のために入れた。VIP を廃止した後も、swfs の各サービスは -ip.bind で
  # 自ノードの IP に bind するため、IP の付与より先に起動しても失敗しないよう残す
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

  # keepalived (SeaweedFS の VIP) を撤去した後も、notify スクリプトが書いた状態ファイルがノードに残り、
  # node-exporter が古い keepalived_instance_state を出し続けるため削除する
  systemd.tmpfiles.rules = [
    "r /var/lib/prometheus/node-exporter/keepalived_VI_SWFS.prom - - - - -"
  ];

  system.autoUpgrade.healthCheck.requiredUnits = [
    "swfs-master.service"
    "swfs-volume.service"
    "swfs-filer.service"
  ];
}
