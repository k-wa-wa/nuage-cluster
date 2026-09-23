args@{ pkgs, ... }:

let
  # autoUpgradeSchedule は各ホストの nixosConfigurations (nix/flake.nix) の
  # specialArgs 経由で渡される。未指定のホストはデフォルト (dates = "daily") にフォールバックする。
  # enable (初回起動トリガーのため tar 側に焼き込む必要がある) は modules/bootstrap.nix 側で扱う。
  autoUpgradeSchedule = args.autoUpgradeSchedule or { };
  autoUpgradeDates = autoUpgradeSchedule.dates or "daily";
in

{
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  time.timeZone = "Asia/Tokyo";

  # nixpkgs のデフォルト値変更 (例: 26.05 での dbus -> dbus-broker) に自動追従させない。
  # デフォルト変更が switch inhibitor に該当する場合、自動アップグレードのライブ switch 中に
  # ハングする既知の nixpkgs バグ (NixOS/nixpkgs#428577) を踏むため、明示的に固定する。
  services.dbus.implementation = "broker";

  environment.systemPackages = [ pkgs.git ];

  system.autoUpgrade.dates = autoUpgradeDates;

  # nix-daemon がトークンファイルを読み込む (ファイルが存在しない場合はエラーにならない)
  systemd.services.nix-daemon.serviceConfig.EnvironmentFile =
    "-/var/lib/nix-provisioning/access-tokens-env";
}
