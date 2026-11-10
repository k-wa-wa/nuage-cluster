args@{ pkgs, ... }:

let
  # autoUpgradeSchedule は各ホストの nixosConfigurations (nix/flake.nix) の
  # specialArgs 経由で渡される。未指定のホストはデフォルト (dates = "daily") にフォールバックする。
  # enable (初回起動トリガーのため tar 側に焼き込む必要がある) は modules/bootstrap.nix 側で扱う。
  autoUpgradeSchedule = args.autoUpgradeSchedule or { };
  autoUpgradeDates = autoUpgradeSchedule.dates or "daily";
in

{
  imports = [
    ./agent-user.nix
    ./journald-upload.nix
    ./auto-upgrade-rollback.nix
  ];

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

  boot.kernel.sysctl = {
    # 接続キューの拡大（バースト耐性・再接続時の接続拒否防止）
    "net.core.somaxconn" = 32768;

    # TCP 送受信バッファ上限を 16MB に拡大（BDP最適化・S3等の大容量転送の頭打ち解消）
    "net.ipv4.tcp_rmem" = "4096 87380 16777216";
    "net.ipv4.tcp_wmem" = "4096 65536 16777216";

    # アイドル後のスロースタート抑制（Keep-Alive / コネクションプールの初速改善）
    "net.ipv4.tcp_slow_start_after_idle" = 0;

    # TIME_WAIT ソケットの再利用（LB / プロキシでのポート枯渇防止）
    "net.ipv4.tcp_tw_reuse" = 1;
  };
}
