{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [
    ./minio.nix
    ./keepalived.nix
    ../../modules/node-exporter-systemd.nix
  ];

  # 26.05 で minio パッケージが insecure マークされ (複数の CVE・アップストリーム放棄)、
  # 明示的な許可がないと評価が失敗するようになった。
  # ここでは 26.05 への更新を優先し一時的に許可するが、恒久対応ではない。
  # 代替ストレージ (Garage, SeaweedFS, Ceph 等) への移行検討は別 Issue で扱うこと。
  nixpkgs.config.permittedInsecurePackages = [
    "minio-2025-10-15T17-29-55Z"
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
