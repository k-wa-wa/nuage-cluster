{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.autopilot;

  # 設定は ./config.yaml を /etc へコピーして使う。
  # systemd の ExecStart と手動実行が同じ実体を見るように、
  # /nix/store ではなくこの固定パスを参照させる。
  configPath = "/etc/autopilot/config.yaml";

  # 手動実行用のラッパー。
  # v4 は AUTOPILOT_HOME / AUTOPILOT_CONFIG を環境変数で受けるので、
  # v3 のような引数の補完は要らない。secrets.env を読んで環境を揃えるだけ。
  autopilotWrapped = pkgs.writeShellScriptBin "autopilot" ''
    if [ -f "${cfg.environmentFile}" ]; then
      set -a
      # shellcheck disable=SC1090
      . "${cfg.environmentFile}"
      set +a
    fi
    export AUTOPILOT_HOME="''${AUTOPILOT_HOME:-${cfg.stateDir}}"
    export AUTOPILOT_CONFIG="''${AUTOPILOT_CONFIG:-${configPath}}"
    exec ${lib.getExe cfg.package} "$@"
  '';
in
{
  environment.etc."autopilot/config.yaml".source = ./config.yaml;

  services.autopilot = {
    enable = true;

    configFile = configPath;

    # claude を /home/nixos/.local/bin に入れているため、
    # 専用ユーザーを作らず nixos ユーザーで動かす。
    user = "nixos";
    group = "users";
    createUser = false;

    # GH_TOKEN を置く。bot-wa-wa の PAT（v2 から流用でよい）。
    # 人間（k-wa-wa）本人のトークンを置くと自己トリガーの無限ループになるため、
    # doctor が「GH_TOKEN の所有者が allowlist に含まれている」として起動を拒否する。
    environmentFile = "/var/lib/autopilot/secrets.env";

    # 対象リポジトリのビルド・テストに必要なツール（devtools.nix）をそのまま通す。
    # git と gh は autopilot のパッケージが wrapProgram で PATH に入れるので、ここでは不要。
    extraPackages = config.environment.systemPackages;
    extraPath = [ "/home/nixos/.local" ];

    # config.yaml で dashboard.host = 0.0.0.0 にしているので、ポートも開ける。
    openFirewall = true;
  };

  # v4 はまだ実 GitHub に対して一周していないため、当面は自動起動させない。
  # `systemctl start autopilot` で任意に起動し、journalctl を見ながら確かめる。
  # 常用に切り替えるときはこの行を消す。
  systemd.services.autopilot.wantedBy = lib.mkForce [ ];

  # config.yaml の更新時に systemd サービスが自動再起動するようにトリガーを設定する。
  systemd.services.autopilot.restartTriggers = [
    config.environment.etc."autopilot/config.yaml".source
  ];

  # サービスを起動しないと StateDirectory が作られないため、
  # doctor を手動実行できるようここで先に作る。
  # v4 は AUTOPILOT_HOME 配下に run/（プロンプトと結果ファイル）と
  # autopilot.lock（多重起動の防止）も作る。
  systemd.tmpfiles.rules = [
    "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
    "d ${cfg.stateDir}/workspaces 0750 ${cfg.user} ${cfg.group} -"
    "d ${cfg.stateDir}/logs 0750 ${cfg.user} ${cfg.group} -"
    "d ${cfg.stateDir}/run 0750 ${cfg.user} ${cfg.group} -"
  ];

  # secrets.env と AUTOPILOT_HOME を自動で揃える autopilot ラッパーを配置する。
  environment.systemPackages = [ autopilotWrapped ];
}
