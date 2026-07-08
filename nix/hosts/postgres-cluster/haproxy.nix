{ pkgs, ... }:

{
  services.haproxy = {
    enable = true;
    config = ''
      defaults
          mode    tcp
          timeout connect 5000ms
          timeout client  50000ms
          timeout server  50000ms

      # 書き込み用フロントエンド（ポート 5430）
      frontend pg-primary-in
          bind *:5430
          default_backend pg-primary

      # PatroniのREST APIを使ってプライマリ（書き込み可能）ノードを検出する
      backend pg-primary
          mode tcp
          option httpchk GET /primary
          http-check expect status 200
          default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
          server pg-cluster-1 10.20.1.41:5432 maxconn 100 check port 8008
          server pg-cluster-2 10.20.1.42:5432 maxconn 100 check port 8008
          server pg-cluster-3 10.20.1.43:5432 maxconn 100 check port 8008

      # 読み取り用フロントエンド（ポート 5431）
      frontend pg-replica-in
          bind *:5431
          default_backend pg-replica

      # PatroniのREST APIを使ってレプリカ（読み取り専用）ノードを検出する
      backend pg-replica
          mode tcp
          option httpchk GET /replica
          http-check expect status 200
          default-server inter 3s fall 3 rise 2
          server pg-cluster-1 10.20.1.41:5432 maxconn 100 check port 8008
          server pg-cluster-2 10.20.1.42:5432 maxconn 100 check port 8008
          server pg-cluster-3 10.20.1.43:5432 maxconn 100 check port 8008
    '';
  };

  # HAProxyが待ち受けるポート（5430, 5431）をファイアウォールで開放する
  networking.firewall.allowedTCPPorts = [ 5430 5431 ];
}
