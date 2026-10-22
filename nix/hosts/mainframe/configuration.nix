{ ... }:

# MVS 3.8j (MVS/CE) を Hercules 上で常駐させるメインフレーム LXC。
# 用語と構成の解説は docs/mainframe.md を参照する。

{
  imports = [
    ./hercules.nix
    ./mvs-config.nix
    ./printer.nix
    ./job-metrics.nix
    ./terminal.nix
    ../../modules/node-exporter-systemd.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  # 各ノードのメトリクス収集用ノードエクスポーターを有効化する。
  # node-exporter-systemd.nix により hercules.service の稼働状態も取れる
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    extraFlags = [
      "--collector.textfile.directory=/var/lib/prometheus/node-exporter"
    ];
  };

  networking.firewall.allowedTCPPorts = [ 9100 ];
}
