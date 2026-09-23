args@{ lib, ... }:

let
  # autoUpgradeSchedule.enable は各ホストの nixosConfigurations (nix/flake.nix) の
  # specialArgs 経由で渡される。未指定のホストはデフォルト (enable = true) にフォールバックする。
  # dates (実行時刻) は運用中に育てていく設定のため modules/common.nix 側で扱う。
  autoUpgradeSchedule = args.autoUpgradeSchedule or { };
  autoUpgradeEnable = autoUpgradeSchedule.enable or true;
in

{
  # base-lxc / base-vm イメージ (tar) に焼き込まれる最小限の定義。
  # ここには「初回起動時に自分自身の本設定へ自己切り替えするために必須の内容」だけを置き、
  # 実質的に不変として扱う。日々継ぎ足していく運用設定は modules/common.nix 側に置くこと。

  nix.settings = {
    trusted-users = [
      "root"
      "nixos"
      "@wheel"
    ];

    trusted-public-keys = [ ];
    substituters = [ "https://cache.nixos.org" ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  # GitHub 疎通不可などで自己設定が失敗した場合でも、必ず人間がログインできるようにするための最終手段。
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

  services.openssh.enable = true;

  networking.useDHCP = false;

  # base-lxc / base-vm 共通: どちらもプロビジョニング時に cloud-init 経由で
  # hostname 等の初期情報を受け取るため。
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  # LXC ホストの初回自己設定トリガー: 起動30秒後に nixos-upgrade が発火し、
  # hostname から nixosConfigurations.<hostname> を自動解決して本設定へ切り替える。
  # VM ホストでは各ホストの nixos-bootstrap が明示的に切り替えを行うが、
  # そのガード (ConditionPathExists) の対象となる nixos-upgrade ユニット自体はここで有効化しておく必要がある。
  system.autoUpgrade = {
    enable = autoUpgradeEnable;
    flake = "https://github.com/k-wa-wa/nuage-cluster/archive/master.tar.gz?dir=nix";
  };

  systemd.timers = lib.mkIf autoUpgradeEnable {
    nixos-upgrade.timerConfig = {
      OnBootSec = "30s";
    };
  };

  system.stateVersion = "24.11";
}
