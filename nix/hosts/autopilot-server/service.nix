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

    # claude を /home/nixos/.local/bin に入れているため、
    # 専用ユーザーを作らず nixos ユーザーで動かす。
    user = "nixos";
    group = "users";
    createUser = false;

    # GH_TOKEN を置く。bot-wa-wa の PAT（v2 から流用でよい）。
    # 人間（k-wa-wa）本人のトークンを置くと、自分の発言を Worker 自身の発言として
    # 全部無視するため、パイプラインが無言で停止する。
    environmentFile = "/var/lib/autopilot/secrets.env";

    # 対象リポジトリのビルド・テストに必要なツール（devtools.nix）をそのまま通す。
    # git と gh は autopilot のラッパーが PATH に入れるので、ここでは不要。
    extraPackages = config.environment.systemPackages;
    extraPath = [ "/home/nixos/.local" ];
  };

  # v3 は実 GitHub に対して未検証のため、当面は自動起動させない。
  # `systemctl start autopilot` で任意に起動し、journalctl を見ながら確かめる。
  # 常用に切り替えるときはこの行を消す。
  systemd.services.autopilot.wantedBy = lib.mkForce [ ];

  # config.yaml の更新時に systemd サービスが自動再起動するようにトリガーを設定する。
  systemd.services.autopilot.restartTriggers = [
    config.environment.etc."autopilot/config.yaml".source
  ];

  # サービスを起動しないと StateDirectory が作られないため、
  # doctor を手動実行できるようここで先に作る。
  # logs は v3 で追加（エージェントのプロンプトと出力が 1 実行 1 ファイルで残る）。
  systemd.tmpfiles.rules = [
    "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
    "d ${cfg.stateDir}/workspaces 0750 ${cfg.user} ${cfg.group} -"
    "d ${cfg.stateDir}/logs 0750 ${cfg.user} ${cfg.group} -"
  ];

  # secrets.env を自動ロードする autopilot ラッパーを配置する。
  environment.systemPackages = [ autopilotWrapped ];
  networking.firewall.allowedTCPPorts = [ 8787 ];
}
