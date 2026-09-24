{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # lm-server の llama.cpp 用。新しいモデルアーキテクチャへの追従のため unstable を別途ピン留めする。
    # autopilot が follows する nixpkgs-unstable とは独立して更新できるよう分けている。
    nixpkgs-llama-cpp.url = "github:nixos/nixpkgs/nixos-unstable";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

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

  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      nixpkgs-llama-cpp,
      nixpkgs-unstable,
      sops-nix,
      autopilot,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
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
    in
    {
      nixosConfigurations = {
        base-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/base-vm/configuration.nix
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
            ./modules/common.nix
            ./hosts/autopilot-server/configuration.nix
            {
              networking.hostName = "autopilot-server";
            }
          ];
        };

        lb-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "03:30";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/loadbalancer/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "lb-1";
            }
          ];
        };

        lb-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "03:40";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/loadbalancer/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "lb-2";
            }
          ];
        };

        lb-3 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "03:50";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/loadbalancer/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "lb-3";
            }
          ];
        };

        pg-cluster-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "03:00";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/postgres-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "pg-cluster-1";
            }
          ];
        };

        pg-cluster-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "03:10";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/postgres-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "pg-cluster-2";
            }
          ];
        };

        pg-cluster-3 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "03:20";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
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
            ./modules/common.nix
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
            ./modules/common.nix
            ./hosts/chaos-monitor/configuration.nix
            {
              networking.hostName = "chaos-monitor";
            }
          ];
        };

        lm-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            llamaCppPkgs = nixpkgs-llama-cpp.legacyPackages.x86_64-linux;
          };
          modules = [
            ./hosts/base-vm/configuration.nix
            ./modules/common.nix
            ./hosts/lm-server/configuration.nix
            {
              networking.hostName = "lm-server";
            }
          ];
        };

        minio-cluster-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "04:00";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/minio-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "minio-cluster-1";
            }
          ];
        };

        minio-cluster-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "04:10";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/minio-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "minio-cluster-2";
            }
          ];
        };

        # 自動更新は raft の quorum を保つため、10 分ずつずらす
        swfs-cluster-1 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "04:20";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/swfs-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "swfs-cluster-1";
            }
          ];
        };

        swfs-cluster-2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "04:30";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/swfs-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "swfs-cluster-2";
            }
          ];
        };

        swfs-cluster-3 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "04:40";
            };
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/swfs-cluster/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "swfs-cluster-3";
            }
          ];
        };

        bluray-extractor = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            unstablePkgs = import nixpkgs-unstable {
              system = "x86_64-linux";
              config.allowUnfreePredicate =
                pkg:
                builtins.elem (nixpkgs.lib.getName pkg) [
                  "makemkv"
                ];
            };
          };
          modules = [
            ./hosts/base-vm/configuration.nix
            ./modules/common.nix
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
