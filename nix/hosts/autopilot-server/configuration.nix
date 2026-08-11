{ pkgs, lib, ... }:

{
  imports = [
    ./service.nix
    ./devtools.nix
  ];

  networking = {
    hostName = "autopilot-server";
    useDHCP = false;

    nameservers = [ "8.8.8.8" ];
  };

  # claude / agy 用の nix-ld 設定
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    curl
    icu
    nss
    expat
    fuse3
  ];

  # claude / agy をセットアップするスクリプトを配置する。
  system.activationScripts.nuageAutopilotSetupScript = lib.stringAfter [ "users" ] ''
    install -D -m 0755 -o nixos ${./setup.sh} /home/nixos/setup.sh
  '';

  # 外部ホストとしてPrometheusのスクレイプ対象に含めるためのノードエクスポーターを有効化する
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    extraFlags = [ "--collector.systemd" ];
  };

  networking.firewall.allowedTCPPorts = [ 9100 ];
}
