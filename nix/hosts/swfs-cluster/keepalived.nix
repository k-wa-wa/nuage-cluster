{
  config,
  lib,
  pkgs,
  ...
}:

let
  hosts = import ./nodes.nix;

  hostName = config.networking.hostName;
  priority = hosts.${hostName}.priority;

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
      "VI_SWFS") VIP="10.20.1.60/" ;;
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
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/nix-provisioning/sops-key";
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
      vrrp_script chk_swfs {
          # S3 ゲートウェイは認証が有効でも /healthz だけは認証なしで 200 を返す
          script "${pkgs.curl}/bin/curl -s -f http://localhost:9000/healthz"
          interval 2
          weight 10
      }

      vrrp_instance VI_SWFS {
          state BACKUP
          interface eth1
          virtual_router_id 60
          priority ${toString priority}
          advert_int 1
          notify ${keepalivedNotify}

          # sops-nix でレンダリングされた認証ファイルをインクルードする
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.60/24
          }

          track_script {
              chk_swfs
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
