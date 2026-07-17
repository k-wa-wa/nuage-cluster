{
  config,
  lib,
  pkgs,
  ...
}:

let
  keepalivedNotify = pkgs.writeShellScript "keepalived-notify.sh" ''
    TYPE=$1
    NAME=$2
    STATE=$3
    PRIO=$4

    mkdir -p /var/lib/prometheus/node-exporter

    # 状態遷移の並行処理による競合を防ぐため、引数 STATE ではなく実際のIP存在確認で判定する
    case "$NAME" in
      "VI_1") VIP="10.20.1.20/" ;;
      "VI_2") VIP="192.168.5.200/" ;;
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
    # 全ホスト共通の固定値パスを指定
    age.keyFile = "/var/lib/nix-provisioning/sops-key";

    secrets.keepalived_auth_pass = { };

    # authentication ブロック全体をレンダリングするテンプレートを定義
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

  system.activationScripts.prometheus-node-exporter-dir = {
    text = ''
      mkdir -p /var/lib/prometheus/node-exporter
      # 古い統合ファイルをクリーンアップ
      if [ -f /var/lib/prometheus/node-exporter/keepalived.prom ]; then
        rm -f /var/lib/prometheus/node-exporter/keepalived.prom
      fi
      if [ ! -f /var/lib/prometheus/node-exporter/keepalived_VI_1.prom ]; then
        echo 'keepalived_instance_state{instance="VI_1"} 0' > /var/lib/prometheus/node-exporter/keepalived_VI_1.prom
      fi
      if [ ! -f /var/lib/prometheus/node-exporter/keepalived_VI_2.prom ]; then
        echo 'keepalived_instance_state{instance="VI_2"} 0' > /var/lib/prometheus/node-exporter/keepalived_VI_2.prom
      fi
      chmod 755 /var/lib/prometheus/node-exporter
      chmod 644 /var/lib/prometheus/node-exporter/keepalived_*.prom
    '';
  };

  services.keepalived = {
    enable = true;
    extraConfig = ''
      vrrp_instance VI_1 {
          state BACKUP
          interface eth1
          virtual_router_id 1
          priority 100
          advert_int 1
          nopreempt
          notify ${keepalivedNotify}

          # sops-nix でレンダリングされた認証ファイルをインクルード
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.20/24
          }
      }

      vrrp_instance VI_2 {
          state BACKUP
          interface eth2
          virtual_router_id 2
          priority 100
          advert_int 1
          nopreempt
          notify ${keepalivedNotify}

          # sops-nix でレンダリングされた認証ファイルをインクルード
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              192.168.5.200/24
          }
      }
    '';
  };

  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -p vrrp -j ACCEPT
    ip6tables -A nixos-fw -p vrrp -j ACCEPT
  '';
}
