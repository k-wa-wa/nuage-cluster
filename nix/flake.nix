{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-ollama.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-config = {
      url = "github:k-wa-wa/nix-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix/3433ea14fbd9e6671d0ff0dd45ed15ee4c156ffa";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # autopilot (GitHub の Issue / PR を真実源とする自律開発ワーカー) の
    # パッケージと NixOS モジュールを提供する。autopilot-server で使用する。
    #
    # v3 (nuage-autopilot3) から v4 へ移行済み。設定の書式が変わっているため、
    # 差し戻す場合は hosts/autopilot-server/config.yaml も一緒に戻すこと。
    #
    # nixpkgs は unstable に follows させる。v4 は Bun 1.2 以降のテキスト形式 bun.lock を
    # 使っており、24.11 の bun (1.1.31) では読めずビルドが失敗する。
    autopilot = {
      url = "github:k-wa-wa/nuage-autopilot4";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, disko, nixos-generators, nixos-vscode-server, nixpkgs-ollama, nixpkgs-unstable, home-manager, nix-config, sops-nix, autopilot, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      mkBaseLxc = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "proxmox-lxc";
        modules = [
          ./hosts/base-lxc/configuration.nix
        ];
      };

      mkBaseVm = nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "qcow-efi";
        modules = [
          ./hosts/base-vm/configuration.nix
        ];
      };
    in {
      nixosConfigurations = {
        base-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/base-vm/configuration.nix
          ];
        };

        dev-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
            nixos-vscode-server.nixosModules.default
            ./hosts/base-vm/disko-config.nix
            ./hosts/base-vm/configuration.nix
            ./hosts/dev-server/configuration.nix
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = {
                unstablePkgs = import nixpkgs-unstable {
                  system = "x86_64-linux";
                  config.allowUnfree = true;
                };
              };
              home-manager.users.nixos = {
                imports = [
                  "${nix-config}/hosts/nixos/home.nix"
                ];
              };
            }
          ];
        };

        # autopilot の実行ホスト。
        # lm-server / bluray-extractor と同じく base-vm イメージから起動し、
        # cloud-init のホスト名をもとに nixos-bootstrap が本構成を自動適用する。
        autopilot-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            autopilot.nixosModules.autopilot
            ./hosts/base-vm/configuration.nix
            ./hosts/autopilot-server/configuration.nix
            {
              networking.hostName = "autopilot-server";
            }
          ];
        };

        lb-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "03:30"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "lb-1";
            }
          ];
        };

        lb-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "03:40"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "lb-2";
            }
          ];
        };

        lb-3 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "03:50"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "lb-3";
            }
          ];
        };

        pg-cluster-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "03:00"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/postgres-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "pg-cluster-1";
            }
          ];
        };

        pg-cluster-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "03:10"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/postgres-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "pg-cluster-2";
            }
          ];
        };

        pg-cluster-3 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "03:20"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/postgres-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "pg-cluster-3";
            }
          ];
        };

        egress-gateway = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/egress-gateway/configuration.nix
            {
              networking.hostName = "egress-gateway";
            }
          ];
        };

        chaos-monitor = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/chaos-monitor/configuration.nix
            {
              networking.hostName = "chaos-monitor";
            }
          ];
        };

        lm-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/base-vm/configuration.nix
            ./hosts/lm-server/configuration.nix
            {
              networking.hostName = "lm-server";
              services.ollama = {
                enable = true;
                # ここで nixpkgs-ollama (特定のコミット) のパッケージを指定
                package = nixpkgs-ollama.legacyPackages.x86_64-linux.ollama;
                acceleration = "rocm";
                loadModels = [ "batiai/qwen3.6-27b:iq3" ];
                host = "0.0.0.0";
                environmentVariables = {
                  OLLAMA_KEEP_ALIVE = "-1";
                  HSA_OVERRIDE_GFX_VERSION = "11.0.0";
                };
                # curl -s http://localhost:11434/api/generate -d '{"model": "sorc/qwen3.5-claude-4.6-opus:9b", "keep_alive": -1}'
              };
            }
          ];
        };

        minio-cluster-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "04:00"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/minio-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "minio-cluster-1";
            }
          ];
        };

        minio-cluster-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { autoUpgradeSchedule = { dates = "04:10"; }; };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/minio-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "minio-cluster-2";
            }
          ];
        };

        bluray-extractor = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            unstablePkgs = import nixpkgs-unstable {
              system = "x86_64-linux";
              config.allowUnfreePredicate = pkg: builtins.elem (nixpkgs.lib.getName pkg) [
                "makemkv"
              ];
            };
          };
          modules = [
            ./hosts/base-vm/configuration.nix
            ./hosts/bluray-extractor/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "bluray-extractor";
            }
          ];
        };
      };

      packages = forAllSystems (system: {
        base-lxc = mkBaseLxc;
        base-vm = mkBaseVm;
      });
    };
}
