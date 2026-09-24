args@{ lib, config, ... }:

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

  # base-vm は cloud-init で hostname を受け取る (nixos-bootstrap が参照する)。
  # base-lxc の hostname は cloud-init ではなく Proxmox が起動前に /etc/hostname へ直接書き込む。
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

  # nixos-rebuild (switch-to-configuration-ng) には、起動直後のように systemd 側の
  # target がまだ収束しきっていないタイミングで初回switchすると、新規ユニット
  # (今回は haproxy/keepalived/coredns等) が「新規」として認識されず起動されないまま
  # 完了してしまうことがある、という既知の不安定さがある
  # (nixpkgs#23221, #353450, #378535, #347315)。
  # 同じ設定でもう一度switchするだけで正しく起動されることを確認済みなので、
  # 初回の nixos-upgrade 成功直後に一度だけ追加でswitchし直す。
  #
  # 注意: --flake <url> のようにホスト名を省略した自動解決だと、解決先が
  # 現在の世代と同じ場合にアクティベーション自体を丸ごとスキップしてしまい
  # (nixos-upgrade と全く同じ状況を再現してしまう)、この対策が効かない。
  # 明示的に --flake <url>#<hostname> を指定した場合はスキップされず、
  # 毎回きちんとアクティベーションが走ることを実機で確認済みなので、
  # ここでは現在の hostname を明示的に埋め込む。
  systemd.services.nixos-upgrade.unitConfig.OnSuccess = [ "bootstrap-second-switch.service" ];

  systemd.services.bootstrap-second-switch = {
    description = "初回switchで起動されなかった新規ユニットを拾うため、初回のみもう一度switchする";
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      marker=/var/lib/bootstrap-second-switch-done
      if [ -e "$marker" ]; then
        exit 0
      fi
      mkdir -p /var/lib
      touch "$marker"
      hostname=$(cat /proc/sys/kernel/hostname)
      ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --flake "${config.system.autoUpgrade.flake}#$hostname"

      # 2 回目の switch は現在の世代と同じ設定の再適用になるため、初回の switch で起動されなかった
      # 新規ユニットは「新規」として検出されず、上の再 switch だけでは拾えないことがある (swfs-cluster で確認)。
      # multi-user.target の wants のうち未起動のユニットだけを明示的に起動する。
      # 起動済みのユニットには影響せず、通常の起動時に multi-user.target が行う処理と同じである。
      ${config.systemd.package}/bin/systemctl start multi-user.target
    '';
  };

  system.stateVersion = "24.11";
}
