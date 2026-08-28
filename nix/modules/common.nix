args@{ pkgs, lib, ... }:

let
  # hostName は一部のホストのみ specialArgs 経由で渡される (postgres-cluster / minio-cluster / loadbalancer)。
  # 未指定のホストではデフォルトの自動アップグレード設定にフォールバックする。
  hostName = args.hostName or "";

  # ホストごとの nixos-upgrade 自動適用設定。適用時刻が重複しないよう分散させる。
  # ここに列挙されないホストはデフォルト (enable = true, dates = "daily") にフォールバックする。
  autoUpgradeByHost = {
    "pg-cluster-1" = { dates = "03:00"; };
    "pg-cluster-2" = { dates = "03:10"; };
    "pg-cluster-3" = { dates = "03:20"; };
    "lb-1" = { dates = "03:30"; };
    "lb-2" = { dates = "03:40"; };
    "lb-3" = { dates = "03:50"; };
    "minio-cluster-1" = { dates = "04:00"; };
    "minio-cluster-2" = { dates = "04:10"; };
  };

  autoUpgradeCfg = autoUpgradeByHost.${hostName} or { };
  autoUpgradeEnable = autoUpgradeCfg.enable or true;
  autoUpgradeDates = autoUpgradeCfg.dates or "daily";
in

{
  nix.settings = {
    trusted-users = [ "root" "nixos" "@wheel" ];

    trusted-public-keys = [ ];
    substituters = [ "https://cache.nixos.org" ];
    experimental-features = [ "nix-command" "flakes" ];
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIi6KgfT6hU8CWl7Xm7bnKen80++7lHrQ+OqvEuAe+80 nixos-sever"
    ];
  };

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking = {
    useDHCP = false;
  };

  environment.systemPackages = [ pkgs.git ];

  system.autoUpgrade = {
    enable = autoUpgradeEnable;
    flake = "https://github.com/k-wa-wa/nuage-cluster/archive/master.tar.gz?dir=nix";
    dates = autoUpgradeDates;
  };

  systemd.timers.nixos-upgrade.timerConfig = lib.mkIf autoUpgradeEnable {
    OnBootSec = "30s";
  };

  # nix-daemon がトークンファイルを読み込む (ファイルが存在しない場合はエラーにならない)
  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = "-/var/lib/nix-provisioning/access-tokens-env";

  system.stateVersion = "24.11";
}
