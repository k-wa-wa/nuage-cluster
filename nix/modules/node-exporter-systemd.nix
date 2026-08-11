{ ... }:

{
  # node-exporter で systemd unit の状態 (node_systemd_unit_state) を収集する
  # NixOSモジュールのlistOfオプションは各モジュールの値が連結されるため、
  # ホスト側の extraFlags 定義とはこのモジュールが競合しない
  services.prometheus.exporters.node.extraFlags = [ "--collector.systemd" ];
}
