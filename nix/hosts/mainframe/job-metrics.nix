{ pkgs, ... }:

# MVS のバッチジョブの成否をコンソールログ (mvslog.txt) から拾い、
# node-exporter の textfile collector (/var/lib/prometheus/node-exporter/mvs_jobs.prom) に書き出す。

let
  textfileDir = "/var/lib/prometheus/node-exporter";

  mainframe-job-metrics = pkgs.writers.writePython3Bin "mainframe-job-metrics" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./tools/job_metrics.py);
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/prometheus 0755 root root - -"
    "d ${textfileDir} 0755 hercules mainframe - -"
  ];

  # mvslog.txt はコンソールのメッセージのたびに書き換わるため、更新を契機 (systemd.paths) にすると
  # 数秒おきに起動して起動回数の上限 (start-limit-hit) に達し、autoUpgrade の switch が失敗する。
  # 前回の続きから読む作りなので、1 分ごとに起動する
  systemd.timers.mainframe-job-metrics = {
    description = "Export MVS job metrics every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };

  systemd.services.mainframe-job-metrics = {
    description = "Export MVS job metrics for node-exporter";
    serviceConfig = {
      Type = "oneshot";
      User = "hercules";
      Group = "mainframe";
      UMask = "0022";
      ExecStart = "${mainframe-job-metrics}/bin/mainframe-job-metrics --prom-file ${textfileDir}/mvs_jobs.prom";
    };
  };
}
