{ config, lib, pkgs, hostName, ... }:

let
  hosts = {
    minio-cluster-1 = { ip = "10.20.1.71"; };
    minio-cluster-2 = { ip = "10.20.1.72"; };
  };

  myIp = hosts.${hostName}.ip;
in
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/${hostName}-key.txt";
    # secrets.yaml から MinIO の認証情報を読み込む
    secrets.minio_root_user = { owner = "minio"; };
    secrets.minio_root_password = { owner = "minio"; };

    # credentials ファイルのテンプレート定義
    templates."minio-credentials" = {
      owner = "minio";
      content = ''
        MINIO_ROOT_USER=${config.sops.placeholder.minio_root_user}
        MINIO_ROOT_PASSWORD=${config.sops.placeholder.minio_root_password}
      '';
    };
  };

  services.minio = {
    enable = true;
    listenAddress = "${myIp}:9000";
    consoleAddress = "${myIp}:9001";
    rootCredentialsFile = config.sops.templates."minio-credentials".path;
    # 2ノード・4ドライブの分散構成エンドポイントを指定する
    dataDir = [
      "http://10.20.1.71:9000/data1"
      "http://10.20.1.71:9000/data2"
      "http://10.20.1.72:9000/data1"
      "http://10.20.1.72:9000/data2"
    ];
  };

  # マウントされた追加ディスクの所有権を設定する
  systemd.tmpfiles.rules = [
    "d /data1 0750 minio minio - -"
    "d /data2 0750 minio minio - -"
  ];

  # ポートを開放する
  networking.firewall.allowedTCPPorts = [ 9000 9001 ];
}
