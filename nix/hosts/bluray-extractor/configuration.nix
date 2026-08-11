{ pkgs, lib, ... }:

{
  imports = [
    ./extract.nix
  ];

  environment.systemPackages = with pkgs; [
    usbutils
    lsof
  ];

  # 外部ホストとしてPrometheusのスクレイプ対象に含めるためのノードエクスポーターを有効化する
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    extraFlags = [ "--collector.systemd" ];
  };

  networking.firewall.allowedTCPPorts = [ 9100 ];
}
