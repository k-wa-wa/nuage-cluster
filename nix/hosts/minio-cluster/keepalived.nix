{ config, lib, pkgs, hostName, ... }:

let
  hosts = {
    minio-cluster-1 = { ip = "10.20.1.71"; };
    minio-cluster-2 = { ip = "10.20.1.72"; };
  };

  myIp = hosts.${hostName}.ip;

  # ホスト名に応じて優先度を決定する
  priority = if hostName == "minio-cluster-1" then 101
             else 100;
in
{
  sops = {
    defaultSopsFile = ./secrets.yaml;
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
      vrrp_script chk_minio {
          script "${pkgs.curl}/bin/curl -s -f http://localhost:9000/minio/health/live"
          interval 2
          weight 10
      }

      vrrp_instance VI_MINIO {
          state BACKUP
          interface eth1
          virtual_router_id 70
          priority ${toString priority}
          advert_int 1

          # sops-nix でレンダリングされた認証ファイルをインクルードする
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.70/24
          }

          track_script {
              chk_minio
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
