{ config, lib, pkgs, ... }:

{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # マウントされたディレクトリ内の各コンテナ固有の秘密鍵ファイルを指定
    age.keyFile = "/var/lib/sops-nix/${config.networking.hostName}-key.txt";

    secrets.keepalived_auth_pass = {};

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

  services.keepalived = {
    enable = true;
    extraConfig = ''
      vrrp_instance VI_1 {
          state BACKUP
          interface eth0
          virtual_router_id 1
          priority 100
          advert_int 1
          nopreempt

          # sops-nix でレンダリングされた認証ファイルをインクルード
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              10.20.1.20/24
          }
      }

      vrrp_instance VI_2 {
          state BACKUP
          interface eth1
          virtual_router_id 2
          priority 100
          advert_int 1
          nopreempt

          # sops-nix でレンダリングされた認証ファイルをインクルード
          include ${config.sops.templates."keepalived-auth.conf".path}

          virtual_ipaddress {
              192.168.5.200/24
          }
      }
    '';
  };
}

