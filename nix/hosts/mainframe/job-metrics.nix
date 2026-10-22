{ pkgs, ... }:

# MVS のバッチジョブの成否をコンソールログ (mvslog.txt) から拾い、
# node-exporter の textfile collector (/var/lib/prometheus/node-exporter/mvs_jobs.prom) に書き出す。

let
  stateDir = "/var/lib/mainframe";
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

  systemd.paths.mainframe-job-metrics = {
    description = "Watch MVS console log for job completion";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = "${stateDir}/mvslog.txt";
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
