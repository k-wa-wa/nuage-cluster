{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.autopilot;

  # 設定は ./config.yaml を /etc へコピーして使う。
  # systemd の ExecStart と手動の `autopilot doctor -c` が同じ実体を見るように、
  # /nix/store ではなくこの固定パスを参照させる。
  configPath = "/etc/autopilot/config.yaml";

  # 手動実行用: secrets.env のロードと config.yaml の自動指定を行うラッパー
  autopilotWrapped = pkgs.writeShellScriptBin "autopilot" ''
    if [ -f "${cfg.environmentFile}" ]; then
      set -a
      # shellcheck disable=SC1090
      . "${cfg.environmentFile}"
      set +a
    fi

    # -c または --config が未指定の場合、既定で ${configPath} を補完する
    has_config=0
    for arg in "$@"; do
      case "$arg" in
        -c|--config|--config=*)
          has_config=1
          ;;
      esac
    done

    if [ "$has_config" -eq 0 ] && [ "$#" -gt 0 ]; then
      case "$1" in
        -h|--help|help)
          exec ${lib.getExe cfg.package} "$@"
          ;;
        *)
          cmd="$1"
          shift
          exec ${lib.getExe cfg.package} "$cmd" -c "${configPath}" "$@"
          ;;
      esac
    fi

    exec ${lib.getExe cfg.package} "$@"
  '';
in
{
  environment.etc."autopilot/config.yaml".source = ./config.yaml;

  services.autopilot = {
    enable = true;

    configFile = configPath;

    # claude / agy を /home/nixos/.local/bin に入れているため、
    # 専用ユーザーを作らず nixos ユーザーで動かす。
    user = "nixos";
    group = "users";
    createUser = false;

    environmentFile = "/var/lib/autopilot/secrets.env";

    # 対象リポジトリのビルド・テストに必要なツール（devtools.nix）をそのまま通す。
    extraPackages = config.environment.systemPackages;
    extraPath = [ "/home/nixos/.local" ];
  };

  # 手動検証フェーズのため、起動はさせない（`systemctl start autopilot` で任意に起動できる）。
  systemd.services.autopilot.wantedBy = lib.mkForce [ ];

  # サービスを起動しないと StateDirectory が作られないため、
  # doctor を手動実行できるようここで先に作る。
  systemd.tmpfiles.rules = [
    "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
    "d ${cfg.stateDir}/workspaces 0750 ${cfg.user} ${cfg.group} -"
  ];

  # secrets.env を自動ロードする autopilot ラッパーを配置する。
  environment.systemPackages = [ autopilotWrapped ];
}
