{ config, lib, pkgs, hostName, ... }:

let
  # 各ホストのIPとホスト名のマッピングを定義する
  hosts = {
    pg-cluster-1 = { ip = "10.20.1.41"; };
    pg-cluster-2 = { ip = "10.20.1.42"; };
    pg-cluster-3 = { ip = "10.20.1.43"; };
  };

  myIp = hosts.${hostName}.ip;

  # ホスト名に応じて優先度を決定する
  priority = if hostName == "pg-cluster-1" then 102
             else if hostName == "pg-cluster-2" then 101
             else 100;

  keepalivedNotify = pkgs.writeShellScript "keepalived-notify.sh" ''
    TYPE=$1
    NAME=$2
    STATE=$3
    PRIO=$4

    mkdir -p /var/lib/prometheus/node-exporter
    chmod 755 /var/lib/prometheus
    chmod 755 /var/lib/prometheus/node-exporter

    # 状態遷移の並行処理による競合を防ぐため、引数 STATE ではなく実際のIP存在確認で判定する
    case "$NAME" in
      "VI_PG_PRIMARY") VIP="10.20.1.40/" ;;
      "VI_PG_REPLICA") VIP="10.20.1.50/" ;;
      *) VIP="" ;;
    esac

    if [ -n "$VIP" ] && ${pkgs.iproute2}/bin/ip addr | ${pkgs.gnugrep}/bin/grep -q "$VIP"; then
      VAL=1
    else
      if [ "$STATE" = "FAULT" ]; then
        VAL=-1
      else
        VAL=0
      fi
    fi

    echo "keepalived_instance_state{instance=\"$NAME\"} $VAL" > /var/lib/prometheus/node-exporter/keepalived_$NAME.prom.tmp
    chmod 644 /var/lib/prometheus/node-exporter/keepalived_$NAME.prom.tmp
    mv /var/lib/prometheus/node-exporter/keepalived_$NAME.prom.tmp /var/lib/prometheus/node-exporter/keepalived_$NAME.prom
  '';
in
{
  sops = {
    # secrets.yaml 内の keepalived_auth_pass をロードする
    secrets.keepalived_auth_pass = {
      owner = "root";
    };

    # keepalived の認証ブロック用テンプレートを定義する
    templates."keepalived-auth.conf" = {
      content = ''
        authentication {
            auth_type PASS
            auth_pass ${config.sops.placeholder.keepalived_auth_pass}
        }
      '';
      owner = "root";
    };
  };

  services.keepalived = {
    enable = true;
    extraConfig = ''
      vrrp_script chk_pg_primary {
          script "${pkgs.curl}/bin/curl -s -f http://${myIp}:8008/primary"
          interval 2
          weight 10
      }

      vrrp_script chk_pg_replica {
          script "${pkgs.curl}/bin/curl -s -f http://${myIp}:8008/replica"
          interval 2
          weight 10
      }

      vrrp_instance VI_PG_PRIMARY {
          state BACKUP
          interface eth1
          virtual_router_id 40
          priority ${toString priority}
          advert_int 1
          notify ${keepalivedNotify}

          # sops-nix でレンダリングされた認証ファイルをインクルードする
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.40/24
          }

          track_script {
              chk_pg_primary
          }
      }

      vrrp_instance VI_PG_REPLICA {
          state BACKUP
          interface eth1
          virtual_router_id 50
          priority ${toString priority}
          advert_int 1
          notify ${keepalivedNotify}

          # sops-nix でレンダリングされた認証ファイルをインクルードする
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.50/24
          }

          track_script {
              chk_pg_replica
          }
      }
    '';
  };

  # VRRP通信用のパケットをファイアウォールで許可する
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p vrrp -j ACCEPT
    ip6tables -A nixos-fw -p vrrp -j ACCEPT
  '';
}
