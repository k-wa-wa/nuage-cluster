{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    
    # Colmena 本体
    colmena.url = "github:zhaofengli/colmena";
    
    # イメージ生成用
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # deploy-rs (予備・比較用)
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, colmena, nixos-generators, deploy-rs, ... }:
    let
      # Linux上で実行する場合も、Macからの操作を考慮して両方入れておきます
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      # LXCイメージ生成関数
      mkLxc = hostName: confPath: nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "proxmox-lxc";
        modules = [ confPath ];
      };
    in {
      # 1. Colmena 設定 (Hive)
      colmena = {
        meta = {
          # Ubuntu上で実行するなら、自分自身のnixpkgsをそのまま利用
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
          # 特殊なSSHオプションが必要な場合はここで指定
          # sshArgs = [ "-o" "IdentitiesOnly=yes" ];
        };

        lb-1 = {
          deployment = {
            targetHost = "192.168.5.201";
            targetUser = "root";
            # Ubuntu上の鍵パスを指定
            # sshKeyPath = "/home/youruser/.ssh/id_ed25519";
          };
          # configuration.nix を読み込む
          imports = [ ./hosts/shared-lb/configuration.nix ];
        };
      };

      # 2. 標準の NixOS 設定 (nixos-rebuild や deploy-rs 用)
      nixosConfigurations.lb-1 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/shared-lb/configuration.nix ];
      };

      # 3. 既存のパッケージ出力 (ビルド用)
      packages = forAllSystems (system: {
        shared-lb = mkLxc "shared-lb" ./hosts/shared-lb/configuration.nix;
      });

      # 4. deploy-rs 用の設定 (予備)
      deploy.nodes.lb-1 = {
        hostname = "192.168.5.201";
        profiles.system = {
          user = "root";
          path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.lb-1;
        };
      };
    };
}
