{ config, lib, pkgs, hostName, ... }:

let
  # ホスト名に応じて優先度を決定する
  priority = if hostName == "pg-cluster-1" then 102
             else if hostName == "pg-cluster-2" then 101
             else 100;
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
      vrrp_instance VI_PG_PRIMARY {
          state BACKUP
          interface eth1
          virtual_router_id 40
          priority ${toString priority}
          advert_int 1
          nopreempt

          # sops-nix でレンダリングされた認証ファイルをインクルードする
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.40/24
          }
      }

      vrrp_instance VI_PG_REPLICA {
          state BACKUP
          interface eth1
          virtual_router_id 50
          priority ${toString priority}
          advert_int 1
          nopreempt

          # sops-nix でレンダリングされた認証ファイルをインクルードする
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.50/24
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
