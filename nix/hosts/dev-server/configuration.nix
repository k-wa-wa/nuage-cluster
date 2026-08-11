{ pkgs, lib, ... }:

{
  imports = [
    ./vscode.nix
  ];

  networking = {
    hostName = "dev-server";
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  programs.zsh.enable = true;
  users.users.nixos.shell = pkgs.zsh;

  virtualisation.docker = {
    # enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        dns = [ "8.8.8.8" "8.8.4.4" ];
      };
    };
  };
  # users.users.nixos.extraGroups = [ "docker" ];

  # 外部ホストとしてPrometheusのスクレイプ対象に含めるためのノードエクスポーターを有効化する
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    extraFlags = [ "--collector.systemd" ];
  };

  networking.firewall.allowedTCPPorts = [ 9100 ];
}
