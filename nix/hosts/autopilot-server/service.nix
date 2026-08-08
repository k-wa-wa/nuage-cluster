{
  pkgs,
  lib,
  config,
  nuage-autopilot,
  ...
}:

let
  repositories = [
    "k-wa-wa/pechka"
    "k-wa-wa/nuage-cluster"
    "k-wa-wa/nuage-monitoring-stack"
    "k-wa-wa/bare-web-proxy"
    "k-wa-wa/nuage-workspace"
    "k-wa-wa/nuage-autopilot"
  ];
  reposArg = lib.concatStringsSep "," repositories;
  pkg = nuage-autopilot.packages.${pkgs.system}.nuage-autopilot;
in
{
  # 単一の常駐プロセスとして poll/work/resync/watchdog の 4 goroutine を動かす
  # （autopilot/DESIGN.md 5章・16章）。oneshot + timer 構成から、この 1 service のみに
  # 統合した。間隔はプロセス内部が管理するため timer unit は使わない。
  systemd.services.nuage-autopilot = {
    description = "nuage-autopilot";

    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = config.environment.systemPackages ++ [
      "/home/nixos/.local"
    ];

    environment.NUAGE_STATE_DIR = "/var/lib/nuage-autopilot";

    serviceConfig = {
      Type = "notify";
      NotifyAccess = "main";
      WatchdogSec = "120s";
      Restart = "always";
      RestartSec = "10s";

      StateDirectory = "nuage-autopilot";

      EnvironmentFile = "-/var/lib/nuage-autopilot/secrets.env";

      # 実行中の claude に猶予を与えて終了させるため長めに取る。
      TimeoutStopSec = "5m";

      ExecStart = "${lib.getExe pkg} --repos ${reposArg} --verify-cli=agy --verify-model=gemini-3.6-flash-high";

      User = "nixos";
    };
  };
}
