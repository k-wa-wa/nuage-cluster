{ ... }:

{
  # 全ホスト共通の Node Exporter 設定。
  # systemd unit の状態収集 (node_systemd_unit_state) も有効化する。
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    openFirewall = true;
    enabledCollectors = [ "systemd" ];
  };
}
