{
  config,
  pkgs,
  lib,
  hostName,
  ...
}:

let
  # 各ホストのIPとホスト名のマッピングを定義する
  hosts = {
    pg-cluster-1 = {
      ip = "10.20.1.41";
    };
    pg-cluster-2 = {
      ip = "10.20.1.42";
    };
    pg-cluster-3 = {
      ip = "10.20.1.43";
    };
  };

  hostname = hostName;
  myIp = hosts.${hostname}.ip;

  # 他ノードのIPリストを生成する
  otherIps = lib.mapAttrsToList (name: val: val.ip) (
    lib.filterAttrs (name: val: name != hostname) hosts
  );

  # DCS（etcd）のホストアドレスリストを生成する
  etcdHosts = lib.mapAttrsToList (name: val: "${val.ip}:2379") hosts;
in
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # 復号に使用するキーファイルのパスを指定する
    age.keyFile = "/var/lib/nix-provisioning/sops-key";

    secrets = {
      pg_superuser_password = {
        owner = "patroni";
      };
      pg_replication_password = {
        owner = "patroni";
      };
      pg_pechka_username = {
        owner = "patroni";
      };
      pg_pechka_password = {
        owner = "patroni";
      };
    };
  };

  services.patroni = {
    enable = true;
    postgresqlPackage = pkgs.postgresql_15;
    scope = "postgres-cluster";
    name = hostname;
    nodeIp = myIp;
    otherNodesIps = otherIps;

    # sops-nixで復号されたファイルからパスワード環境変数を読み込ませる
    environmentFiles = {
      PATRONI_SUPERUSER_PASSWORD = config.sops.secrets.pg_superuser_password.path;
      PATRONI_REPLICATION_PASSWORD = config.sops.secrets.pg_replication_password.path;
      PECHKA_USERNAME = config.sops.secrets.pg_pechka_username.path;
      PECHKA_PASSWORD = config.sops.secrets.pg_pechka_password.path;
    };

    settings = {
      # DCSとしてetcd3を使用する設定
      etcd3 = {
        hosts = etcdHosts;
      };

      postgresql = {
        listen = lib.mkForce "0.0.0.0:5432";
        connect_address = lib.mkForce "${myIp}:5432";
        parameters = {
          unix_socket_directories = "/tmp";
        };
        authentication = {
          superuser = {
            username = "postgres";
            password = "$PATRONI_SUPERUSER_PASSWORD";
          };
          replication = {
            username = "replication";
            password = "$PATRONI_REPLICATION_PASSWORD";
          };
        };
      };

      bootstrap = {
        # 初期化時に一度だけ実行されるスクリプト
        post_init = pkgs.writeShellScript "post-init" ''
          # 第一引数で渡される接続URLを使用して、ユーザーとデータベースを作成する
          ${pkgs.postgresql_15}/bin/psql "$1" -c "CREATE USER \"$PECHKA_USERNAME\" WITH PASSWORD '$PECHKA_PASSWORD';"
          ${pkgs.postgresql_15}/bin/psql "$1" -c "CREATE DATABASE \"pechka\" OWNER \"$PECHKA_USERNAME\";"
        '';

        users = {
          superuser = {
            username = "postgres";
            password = "$PATRONI_SUPERUSER_PASSWORD";
          };
          replication = {
            username = "replication";
            password = "$PATRONI_REPLICATION_PASSWORD";
          };
        };

        dcs = {
          ttl = 30;
          loop_wait = 10;
          retry_timeout = 10;
          maximum_lag_on_failover = 1048576;
          postgresql = {
            use_pg_rewind = true;
            use_slots = true;
            parameters = {
              max_connections = 100;
              shared_buffers = "1GB";
              archive_mode = "on";
              archive_command = "true";
              wal_level = "replica";
              max_wal_senders = 10;
              max_replication_slots = 10;
              hot_standby = "on";
              unix_socket_directories = "/tmp";
            };
          };
        };
        initdb = [
          "encoding=UTF8"
          "data-checksums"
        ];
        pg_hba = [
          "host replication replication 10.20.1.0/24 md5"
          "host all all 10.20.1.0/24 md5"
          "host all all 127.0.0.1/32 md5"
          "host all all ::1/128 md5"
          "host all all all md5"
        ];
      };
    };
  };

  # Patroni API（8008）とPostgreSQL（5432）のポートを開放する
  networking.firewall.allowedTCPPorts = [
    8008
    5432
  ];
}
