{ config, lib, pkgs, ... }:

{
  sops = {
    defaultSopsFile = ./secrets.yaml;
    # 全ホスト共通の固定値パスを指定
    age.keyFile = "/var/lib/sops-nix/key.txt";

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

  # 起動時にコンテナのホスト名に応じた秘密鍵へのシンボリックリンクを作成
  system.activationScripts.sops-key-link = {
    text = ''
      HOSTNAME=$(cat /etc/hostname | tr -d '\n')
      mkdir -p /var/lib/sops-nix
      if [ -f "/var/lib/sops-nix/$HOSTNAME-key.txt" ]; then
        ln -sf "/var/lib/sops-nix/$HOSTNAME-key.txt" /var/lib/sops-nix/key.txt
      fi
    '';
  };
  # sops-nix の復号スクリプトの前に実行するよう依存関係を指定
  system.activationScripts.setupSecrets.deps = [ "sops-key-link" ];

  services.keepalived = {
    enable = true;
    openFirewall = true;
    extraConfig = ''
      vrrp_instance VI_1 {
          state BACKUP
          interface eth1
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
          interface eth2
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

