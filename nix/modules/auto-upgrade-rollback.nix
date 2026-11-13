{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.system.autoUpgrade.healthCheck;

  nixosRebuild = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild";
  systemctl = "${config.systemd.package}/bin/systemctl";

  pathPackages = [
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    config.systemd.package
  ];

  # 更新開始前の現行プロファイルを記録するスクリプト
  preCheckScript = pkgs.writeShellScript "nixos-upgrade-pre-check" ''
    set -u
    mkdir -p /run/nixos-upgrade
    rm -f /run/nixos-upgrade/pre-upgrade-profile
    ${pkgs.coreutils}/bin/readlink -f /nix/var/nix/profiles/system > /run/nixos-upgrade/pre-upgrade-profile
  '';

  # 自動ヘルスチェック＆ロールバックスクリプト
  healthcheckScript = pkgs.writeShellScript "nixos-upgrade-post-check" ''
        set -u

        export PATH="${lib.makeBinPath pathPackages}:$PATH"

        LOG_FILE="/var/log/nixos-rollback.log"
        HOSTNAME=$(cat /proc/sys/kernel/hostname 2>/dev/null || uname -n)

        log() {
          local msg="[$(date -Iseconds)] [$HOSTNAME] $*"
          echo "$msg"
          echo "$msg" >> "$LOG_FILE"
        }

        log_error() {
          local msg="[$(date -Iseconds)] [$HOSTNAME] ERROR: $*"
          echo "$msg" >&2
          echo "$msg" >> "$LOG_FILE"
        }

        write_metrics() {
          local rollback_status="$1"
          local last_status="$2"
          local metric_dir="/var/lib/prometheus/node-exporter"

          if [ -d "$metric_dir" ]; then
            local tmp_file="$metric_dir/nixos_upgrade.prom.tmp"
            local prom_file="$metric_dir/nixos_upgrade.prom"
            local now
            now=$(date +%s)
            cat <<EOF > "$tmp_file"
    # HELP nixos_upgrade_rollback_status Status of nixos-upgrade auto-rollback (0: normal, 1: rolled back)
    # TYPE nixos_upgrade_rollback_status gauge
    nixos_upgrade_rollback_status $rollback_status
    # HELP nixos_upgrade_last_status Result of last nixos-upgrade run (1: success, 0: failure/rolled back)
    # TYPE nixos_upgrade_last_status gauge
    nixos_upgrade_last_status $last_status
    # HELP nixos_upgrade_last_timestamp Unix timestamp of last nixos-upgrade execution
    # TYPE nixos_upgrade_last_timestamp gauge
    nixos_upgrade_last_timestamp $now
    EOF
            chmod 644 "$tmp_file"
            mv -f "$tmp_file" "$prom_file"
          fi
        }

        # 1. 初回ブートストラップガード
        # LXC では bootstrap-second-switch-done、VM では nixos-bootstrap-done が存在しない場合、
        # 初回自己切り替え中のためロールバックや健全性判定はスキップする。
        if [ ! -f /var/lib/bootstrap-second-switch-done ] && [ ! -f /var/lib/nixos-bootstrap-done ]; then
          echo "First-time bootstrap in progress. Skipping auto-rollback healthcheck."
          exit 0
        fi

        # 2. 更新前後のプロファイルおよび世代確認
        pre_profile=$(cat /run/nixos-upgrade/pre-upgrade-profile 2>/dev/null || true)
        current_profile=$(readlink -f /nix/var/nix/profiles/system || true)
        current_link=$(readlink /nix/var/nix/profiles/system || true)
        current_gen=$(echo "$current_link" | sed -n 's/.*system-\([0-9]*\)-link/\1/p')

        # 新世代に切り替わったかどうか (プロファイルが変化したか)
        generation_changed=unknown
        if [ -n "$pre_profile" ] && [ -n "$current_profile" ] && [ "$pre_profile" != "$current_profile" ]; then
          generation_changed=true
        elif [ -n "$pre_profile" ] && [ -n "$current_profile" ]; then
          generation_changed=false
        fi

        can_rollback=false
        if [ -n "$current_gen" ] && [ "$current_gen" -gt 1 ]; then
          can_rollback=true
        fi

        rollback() {
          local reason="$1"
          log_error "Auto-rollback triggered: $reason"
          log "Pre-upgrade profile: $pre_profile"
          log "Current profile before rollback: $current_profile (generation $current_gen)"

          if [ "$can_rollback" != "true" ]; then
            log_error "Cannot rollback: No previous generation available (current generation: $current_gen)"
            write_metrics 1 0
            return 1
          fi

          log "Executing: ${nixosRebuild} switch --rollback"
          if ${nixosRebuild} switch --rollback >> "$LOG_FILE" 2>&1; then
            local new_profile
            new_profile=$(readlink -f /nix/var/nix/profiles/system || true)
            log "SUCCESS: Rolled back to $new_profile"
            write_metrics 1 0
            return 0
          else
            log_error "CRITICAL: nixos-rebuild switch --rollback failed!"
            write_metrics 1 0
            return 1
          fi
        }

        # 3. ExecStart 本体の成否チェック
        if [ "''${SERVICE_RESULT:-}" != "success" ]; then
          if [ "$generation_changed" = "unknown" ]; then
            log_error "nixos-upgrade failed and the previous profile is unknown; cannot determine whether rollback is safe."
            write_metrics 0 0
            exit 1
          fi
          # フェッチ失敗、ビルドエラー、Flake 評価エラー等で新世代が適用されていない場合、
          # 現行の健全な世代のまま稼働しているため、ロールバックは実行しない。
          if [ "$generation_changed" != "true" ]; then
            log_error "nixos-upgrade failed before applying new generation (current profile unchanged: $current_profile)."
            log_error "Skipping rollback because running system generation is intact."
            write_metrics 0 0
            exit 1
          fi

          # 新世代への switch 中に失敗した場合のみロールバックを実行する
          rollback "nixos-upgrade main process failed after switching profile (SERVICE_RESULT=''${SERVICE_RESULT:-unknown}, EXIT_STATUS=''${EXIT_STATUS:-unknown})"
          exit 1
        fi

        # 4. ヘルスチェック（健全性検証）
        log "Starting post-upgrade healthcheck (timeout: ${toString cfg.timeoutSec}s)..."

        # switch 直後の過渡的な状態を避けるため待機
        sleep 5

        required_units=(${toString cfg.requiredUnits})
        deadline=$(( $(date +%s) + ${toString cfg.timeoutSec} ))
        healthy=false

        while true; do
          system_state=$(${systemctl} is-system-running 2>/dev/null || true)
          failed_units=$(${systemctl} list-units --failed --no-legend --plain 2>/dev/null) || failed_units=unknown
          # 起動時はこのサービス自身の start job が終了するまで systemd は starting のままになる。
          # 他の job が残っている場合は起動完了を待ち、失敗や通信エラーも成功と扱わない。
          pending_jobs=$(${systemctl} list-jobs --no-legend --plain 2>/dev/null) || pending_jobs=unknown
          only_upgrade_job=$(printf '%s\n' "$pending_jobs" | awk 'NF { if ($2 == "nixos-upgrade.service" && $3 == "start") own++; else other++ } END { if (own == 1 && other == 0) print "true"; else print "false" }')

          units_ok=true
          for u in "''${required_units[@]}"; do
            if [ -n "$u" ] && ! ${systemctl} is-active --quiet "$u" 2>/dev/null; then
              units_ok=false
              break
            fi
          done

          if [ "$pending_jobs" != "unknown" ] && [ -z "$failed_units" ] && [ "$units_ok" = "true" ] && { [ "$system_state" = "running" ] || { [ "$system_state" = "starting" ] && [ "$only_upgrade_job" = "true" ]; }; }; then
            healthy=true
            break
          fi

          if [ $(date +%s) -ge $deadline ]; then
            break
          fi

          sleep 3
        done

        if [ "$healthy" = "true" ]; then
          log "Healthcheck passed. System is running healthy."
          write_metrics 0 1
          exit 0
        else
          system_state=$(${systemctl} is-system-running 2>/dev/null || true)
          pending_jobs=$(${systemctl} list-jobs --no-legend --plain 2>/dev/null) || pending_jobs=unknown
          failed_units=$(${systemctl} list-units --failed --no-legend --plain 2>/dev/null | cut -d' ' -f1 | tr '\n' ' ' || true)

          failure_detail="system_state=$system_state"
          if [ "$pending_jobs" = "unknown" ]; then
            failure_detail="$failure_detail, pending_jobs=[failed to retrieve]"
          elif [ -n "$pending_jobs" ]; then
            jobs_summary=$(printf '%s\n' "$pending_jobs" | awk '{printf "%s(%s) ", $2, $3}' | sed 's/ $//')
            failure_detail="$failure_detail, pending_jobs=[$jobs_summary]"
          fi
          if [ -n "$failed_units" ]; then
            failure_detail="$failure_detail, failed_units=[$failed_units]"
          fi
          if [ "$units_ok" != "true" ]; then
            failure_detail="$failure_detail, required units not active"
          fi

          # 新世代に切り替わっていない場合 (自ホストの更新差分がない日次自動更新等)、
          # 今回のアップグレードが原因で壊れたわけではないため、過去世代への誤ロールバックを防ぐ。
          if [ "$generation_changed" = "unknown" ]; then
            log_error "Healthcheck failed within ${toString cfg.timeoutSec}s ($failure_detail), and the previous profile is unknown; cannot determine whether rollback is safe."
            write_metrics 0 0
            exit 1
          fi
          if [ "$generation_changed" = "false" ]; then
            log_error "Healthcheck failed within ${toString cfg.timeoutSec}s ($failure_detail), but no new generation was applied (current profile unchanged: $current_profile)."
            log_error "Skipping rollback to avoid rolling back intact past generations."
            write_metrics 0 0
            exit 1
          fi

          rollback "Healthcheck failed within ${toString cfg.timeoutSec}s ($failure_detail)"
          exit 1
        fi
  '';
in
{
  options = {
    system.autoUpgrade.healthCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable automatic health check and rollback for nixos-upgrade.";
      };

      timeoutSec = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Timeout in seconds to wait for system to become healthy after switch.";
      };

      requiredUnits = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "haproxy.service" ];
        description = "Additional required systemd units that must be active after switch.";
      };
    };
  };

  config = lib.mkIf (config.system.autoUpgrade.enable && cfg.enable) {
    systemd.services.nixos-upgrade = {
      serviceConfig = {
        TimeoutStopSec = "10m";
        ExecStartPre = [
          "${preCheckScript}"
        ];
        ExecStopPost = [
          "${healthcheckScript}"
        ];
      };
    };
  };
}
