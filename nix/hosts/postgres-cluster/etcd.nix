{ config, pkgs, lib, hostName, ... }:

let
  # 各ホストのIPとホスト名のマッピングを定義する
  hosts = {
    pg-cluster-1 = { ip = "10.20.1.41"; };
    pg-cluster-2 = { ip = "10.20.1.42"; };
    pg-cluster-3 = { ip = "10.20.1.43"; };
  };

  hostname = hostName;
  myIp = hosts.${hostname}.ip;
in
{
  services.etcd = {
    enable = true;
    name = hostname;
    
    # ピア間通信用リスナーとアドバタイズURLを設定する
    listenPeerUrls = [ "http://0.0.0.0:2380" ];
    initialAdvertisePeerUrls = [ "http://${myIp}:2380" ];

    # クライアント通信用リスナーとアドバタイズURLを設定する
    listenClientUrls = [ "http://0.0.0.0:2379" "http://127.0.0.1:2379" ];
    advertiseClientUrls = [ "http://${myIp}:2379" ];

    # クラスタの初期構成メンバーを指定する
    initialCluster = lib.mapAttrsToList (name: val: "${name}=http://${val.ip}:2380") hosts;
    initialClusterToken = "etcd-postgres-token";
    initialClusterState = "new";

    # etcdが必要とするファイアウォールポート（2379, 2380）を自動で開放する
    openFirewall = true;
  };
}
