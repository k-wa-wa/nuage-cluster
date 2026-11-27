{ config, lib, ... }:

let
  textfileDir = "/var/lib/prometheus/node-exporter";
  cfg = config.services.prometheus.exporters.node.textfile;
in
{
  # 全ホスト共通の Node Exporter 設定。
  # node-exporter で systemd unit の状態 (node_systemd_unit_state) を収集する。
  # extraFlags ではなく enabledCollectors で有効化することで、NixOS モジュール側で
  # RestrictAddressFamilies に AF_UNIX が追加され dbus に接続できるようになる。
  #
  # mainframe のように専用ユーザーが textfile を書くホストと systemd.tmpfiles.rules が
  # 同一パスで競合しないよう、ディレクトリ所有者・権限をオプション化する。
  options.services.prometheus.exporters.node.textfile = {
    owner = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "textfile collector ディレクトリの所有者";
    };
    group = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "textfile collector ディレクトリのグループ";
    };
    mode = lib.mkOption {
      type = lib.types.str;
      default = "0755";
      description = "textfile collector ディレクトリのパーミッション";
    };
  };

  config = {
    services.prometheus.exporters.node = {
      enable = true;
      port = 9100;
      openFirewall = true;
      enabledCollectors = [ "systemd" ];
      extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus 0755 root root - -"
      "d ${textfileDir} ${cfg.mode} ${cfg.owner} ${cfg.group} - -"
    ];
  };
}
