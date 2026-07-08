{ pkgs, lib, config, ... }:

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

  # 各ノードのメトリクス収集用ノードエクスポーターを有効化する
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
  };
}
