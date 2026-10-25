# atelier 上で動く AI Agent の使用量メトリクスを収集し、VictoriaMetrics に送信する。
#
# ~/.claude、~/.gemini、~/.config/orca、workspaces 配下の .autopilot のログを差分パースし、
# Prometheus exposition format で毎分 VictoriaMetrics (10.20.1.20:8427) へ投入する。
{ pkgs, ... }:

let
  user = "nixos";
  collectorScript = ../../../scripts/ai-agent-metrics-collector.py;
in
{
  systemd.user.timers.ai-agent-metrics-collector = {
    description = "AI Agent 使用量メトリクス定期収集タイマー";
    wantedBy = [ "timers.target" ];

    unitConfig = {
      ConditionUser = user;
    };

    timerConfig = {
      OnCalendar = "*:0/1";
      Persistent = true;
    };
  };

  systemd.user.services.ai-agent-metrics-collector = {
    description = "AI Agent 使用量メトリクス収集と VictoriaMetrics 連携";

    unitConfig = {
      ConditionUser = user;
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${collectorScript}";
    };
  };
}
