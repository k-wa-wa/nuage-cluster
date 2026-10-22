{ ... }:

{
  # node-exporter で systemd unit の状態 (node_systemd_unit_state) を収集する。
  # extraFlags ではなく enabledCollectors で有効化することで、NixOS モジュール側で
  # RestrictAddressFamilies に AF_UNIX が追加され dbus に接続できるようになる
  services.prometheus.exporters.node.enabledCollectors = [ "systemd" ];
}
