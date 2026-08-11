{ pkgs, ... }@args:

let
  # hostName は pg-cluster-*/lb-*/minio-cluster-* の nixosConfigurations でのみ
  # specialArgs 経由で渡される。common.nix は全ホスト共通で import されるため、
  # 渡されないホストではエラーにせず null にフォールバックする。
  hostName = args.hostName or null;

  # 冗長構成クラスタ内のノードが同時に自動アップグレード・再起動しないよう、
  # ホストごとに明示的な適用時刻 (system.autoUpgrade.dates 形式) を指定する。
  # 未指定のホストは従来どおり "daily" (時刻は systemd のデフォルト) を使う。
  autoUpgradeDatesByHost = {
    pg-cluster-1 = "02:00";
    pg-cluster-2 = "02:20";
    pg-cluster-3 = "02:40";
    lb-1 = "03:00";
    lb-2 = "03:20";
    lb-3 = "03:40";
    minio-cluster-1 = "04:00";
    minio-cluster-2 = "04:20";
  };

  autoUpgradeDates =
    if hostName != null && builtins.hasAttr hostName autoUpgradeDatesByHost
    then autoUpgradeDatesByHost.${hostName}
    else "daily";
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
    enable = true;
    flake = "https://github.com/k-wa-wa/nuage-cluster/archive/master.tar.gz?dir=nix";
    dates = autoUpgradeDates;
  };

  # dates で決まる OnCalendar に加え、初回プロビジョニング直後の反映を早めるため OnBootSec も設定する
  systemd.timers.nixos-upgrade.timerConfig = {
    OnBootSec = "30s";
  };

  # nix-daemon がトークンファイルを読み込む (ファイルが存在しない場合はエラーにならない)
  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = "-/var/lib/nix-provisioning/access-tokens-env";

  system.stateVersion = "24.11";
}
