{
  config,
  lib,
  pkgs,
  ...
}:

let
  hosts = import ./nodes.nix;

  hostName = config.networking.hostName;
  myIp = hosts.${hostName}.ip;
  allIps = lib.mapAttrsToList (_: h: h.ip) hosts;
  peerIps = lib.filter (ip: ip != myIp) allIps;

  ports = {
    master = 9333;
    volume = 8080;
    filer = 8888;
    # 既存クライアント (pechka, bluray-extractor) が MinIO に接続していたポートに揃える
    s3 = 9000;
  };

  # 全ノードの "ip:port" をカンマ区切りで連結する
  endpoints = port: lib.concatMapStringsSep "," (ip: "${ip}:${toString port}") allIps;

  # master / volume / filer の gRPC ポートは HTTP ポート + 10000 になる
  internalPorts =
    lib.concatMap
      (p: [
        p
        (p + 10000)
      ])
      [
        ports.master
        ports.volume
        ports.filer
      ];

  weed = "${pkgs.seaweedfs}/bin/weed";
  dataDir = "/data";
  stateDir = "/var/lib/swfs";
  s3Config = config.sops.templates."swfs-s3.json".path;

  mkWeedService =
    {
      description,
      args,
      after ? [ ],
      unitConfig ? { },
      serviceConfig ? { },
    }:
    {
      inherit description unitConfig;
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ] ++ after;
      serviceConfig = {
        ExecStart = "${weed} ${lib.escapeShellArgs args}";
        User = "swfs";
        Group = "swfs";
        WorkingDirectory = stateDir;
        Restart = "always";
        RestartSec = 5;
        # filer の leveldb で FD が枯渇するとメタデータ同期が停止するため、上限を引き上げる
        LimitNOFILE = 1048576;
      }
      // serviceConfig;
    };

  # 認証情報を 1 件も読み込めない設定では、4.45 未満の s3 が認証を無効化して全操作を許可する。
  # nixpkgs 26.05 は 4.36 のため、起動前に検証して fail-closed にする。
  # 設定ファイルが存在しない場合も jq が失敗するため、unit は起動しない。
  checkS3Config = pkgs.writeShellScript "swfs-check-s3-config" ''
    ${pkgs.jq}/bin/jq -e '
      [.identities[]?.credentials[]?
        | select((.accessKey // "") != "" and (.secretKey // "") != "")]
      | length > 0
    ' ${s3Config} > /dev/null
  '';
in
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/nix-provisioning/sops-key";
    # secrets.yaml から S3 の認証情報を読み込む
    secrets.swfs_s3_access_key = {
      owner = "swfs";
    };
    secrets.swfs_s3_secret_key = {
      owner = "swfs";
    };

    # S3 ゲートウェイの identity 定義 (s3.json) をテンプレートとして生成する
    templates."swfs-s3.json" = {
      owner = "swfs";
      content = builtins.toJSON {
        identities = [
          {
            name = "admin";
            credentials = [
              {
                accessKey = config.sops.placeholder.swfs_s3_access_key;
                secretKey = config.sops.placeholder.swfs_s3_secret_key;
              }
            ];
            actions = [
              "Admin"
              "Read"
              "Write"
              "List"
              "Tagging"
            ];
          }
          # nginx 経由の匿名配信に必要なプレフィックスだけ読み取りを許可する
          {
            name = "anonymous";
            actions = [
              "Read:pechka/resources/hls/*"
              "Read:pechka/thumbnails/*"
            ];
          }
        ];
      };
    };
  };

  users.users.swfs = {
    isSystemUser = true;
    group = "swfs";
  };
  users.groups.swfs = { };

  # マウントされた追加ディスクと、master / filer のメタデータの所有権を設定する
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 swfs swfs - -"
    "d ${stateDir} 0750 swfs swfs - -"
    "d ${stateDir}/master 0750 swfs swfs - -"
    "d ${stateDir}/filer 0750 swfs swfs - -"
  ];

  systemd.services = {
    # master は raft で 3 台のクラスタを組む。ノード間で同時に起動しても問題ない
    swfs-master = mkWeedService {
      description = "SeaweedFS master";
      args = [
        "master"
        "-ip=${myIp}"
        "-ip.bind=${myIp}"
        "-port=${toString ports.master}"
        "-mdir=${stateDir}/master"
        "-peers=${endpoints ports.master}"
        # 別ノードに 1 コピーを持たせる (計 2 コピー)
        "-defaultReplication=001"
        "-volumeSizeLimitMB=5000"
      ];
    };

    swfs-volume = mkWeedService {
      description = "SeaweedFS volume server";
      after = [ "swfs-master.service" ];
      args = [
        "volume"
        "-ip=${myIp}"
        "-ip.bind=${myIp}"
        "-port=${toString ports.volume}"
        "-dir=${dataDir}"
        # 0 で空き容量から自動計算する
        "-max=0"
        # 空き容量が 5% を下回ったら read-only にして、ディスク枯渇を防ぐ
        "-minFreeSpace=5"
        "-mserver=${endpoints ports.master}"
      ];
    };

    # filer のメタデータは各ノードの leveldb に持ち、ノード間は master 経由で自動同期される
    swfs-filer = mkWeedService {
      description = "SeaweedFS filer";
      after = [ "swfs-master.service" ];
      args = [
        "filer"
        "-ip=${myIp}"
        "-ip.bind=${myIp}"
        "-port=${toString ports.filer}"
        "-master=${endpoints ports.master}"
        "-defaultStoreDir=${stateDir}/filer"
        "-defaultReplicaPlacement=001"
      ];
    };

    # S3 ゲートウェイは全 filer を接続先に指定し、filer 障害時に自動で切り替える
    swfs-s3 = mkWeedService {
      description = "SeaweedFS S3 gateway";
      after = [ "swfs-filer.service" ];
      args = [
        "s3"
        "-filer=${endpoints ports.filer}"
        "-port=${toString ports.s3}"
        "-config=${s3Config}"
        # 使用しない Iceberg REST Catalog の待ち受けを無効化する
        "-port.iceberg=0"
      ];
      serviceConfig.ExecStartPre = checkS3Config;
    };
  };

  # S3 ゲートウェイのポートを開放する
  networking.firewall.allowedTCPPorts = [ ports.s3 ];

  # master / volume / filer の API は認証を持たないため、ピアノードからのみ許可する
  networking.firewall.extraCommands = lib.concatMapStrings (ip: ''
    iptables -A nixos-fw -p tcp -s ${ip} -m multiport --dports ${
      lib.concatMapStringsSep "," toString internalPorts
    } -j ACCEPT
  '') peerIps;
}
