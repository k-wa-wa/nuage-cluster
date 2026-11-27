# Proxmox LXC コンテナでは /proc/loadavg や /proc/pressure/cpu が物理ホスト全体の値を返すため、
# コンテナ単位で分離された /sys/fs/cgroup/cpu.pressure を読み取り、
# node-exporter の textfile collector 向けに出力する。
{ pkgs, ... }:

let
  textfileDir = "/var/lib/prometheus/node-exporter";
  promFile = "${textfileDir}/lxc_cgroup_psi.prom";

  exportPsiMetrics = pkgs.writeShellApplication {
    name = "export-lxc-psi-metrics";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
    ];
    text = ''
      pressure_file="/sys/fs/cgroup/cpu.pressure"
      prom_dir="${textfileDir}"
      prom_file="${promFile}"

      tmp_file=$(mktemp "$prom_dir/lxc_cgroup_psi.prom.tmp.XXXXXX")
      trap 'rm -f "$tmp_file"' EXIT

      LC_ALL=C awk '
        {
          for (i = 2; i <= NF; i++) {
            if ($i ~ /^total=[0-9]+$/) {
              split($i, a, "=")
              if ($1 == "some") {
                some_usec = a[2]
              } else if ($1 == "full") {
                full_usec = a[2]
              }
            }
          }
        }
        END {
          if (some_usec == "" || full_usec == "") {
            print "Failed to parse some/full total from /sys/fs/cgroup/cpu.pressure" > "/dev/stderr"
            exit 1
          }
          printf "# HELP lxc_cgroup_pressure_cpu_waiting_seconds_total Total time in seconds that tasks in this LXC cgroup have waited for CPU.\n"
          printf "# TYPE lxc_cgroup_pressure_cpu_waiting_seconds_total counter\n"
          printf "lxc_cgroup_pressure_cpu_waiting_seconds_total %.6f\n", some_usec / 1000000.0
          printf "# HELP lxc_cgroup_pressure_cpu_stalled_seconds_total Total time in seconds that all tasks in this LXC cgroup were stalled on CPU.\n"
          printf "# TYPE lxc_cgroup_pressure_cpu_stalled_seconds_total counter\n"
          printf "lxc_cgroup_pressure_cpu_stalled_seconds_total %.6f\n", full_usec / 1000000.0
        }
      ' "$pressure_file" > "$tmp_file"

      chmod 644 "$tmp_file"
      mv -f "$tmp_file" "$prom_file"
    '';
  };
in
{
  systemd.timers.lxc-psi-metrics = {
    description = "Export LXC cgroup CPU PSI metrics every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "1min";
      AccuracySec = "10s";
    };
  };

  systemd.services.lxc-psi-metrics = {
    description = "Export LXC cgroup CPU PSI metrics for node-exporter";
    after = [ "systemd-tmpfiles-setup.service" ];
    # base-lxc イメージの初回起動時 (common.nix 適用前) は出力先ディレクトリが存在しないためスキップする。
    unitConfig.ConditionPathExists = textfileDir;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${exportPsiMetrics}/bin/export-lxc-psi-metrics";
    };
  };
}
