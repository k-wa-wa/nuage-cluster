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

    # autopilot5 (Orca の窓口エージェントから任された仕事を裏で完走させる autopilot-run と、
    # 全エージェント共通のルール・スキル) を提供する。atelier で使用する。
    # bun build --compile に新しめの bun が要るため、nixpkgs は unstable に follows させる。
    autopilot5 = {
      url = "github:k-wa-wa/nuage-autopilot5";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # メインフレーム (mainframe) で動かす業務アプリ。各リポジトリが MVS に書き込む資材
    # (members/ schedule datasets.json) を出力し、mvs-config が書き込む。
    # アプリを更新したら `nix flake update nuage-usage-ledger --flake ./nix` で取り込む。
    nuage-usage-ledger = {
      url = "github:k-wa-wa/nuage-usage-ledger";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 3270 端末の画面を案内付きで操作する TUI (汎用のツール)。mainframe ホストでは、基盤と業務アプリの辞書を
    # 足して `ci3270` として入れる (hosts/mainframe/terminal.nix)。
    # 更新したら `nix flake update cicerone3270 --flake ./nix` で取り込む。
    cicerone3270 = {
      url = "github:k-wa-wa/cicerone3270";
      inputs.nixpkgs.follows = "nixpkgs";
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
      autopilot5,
      nuage-usage-ledger,
      cicerone3270,
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

        # エージェントと一緒に開発する作業場 (Orca サーバー + autopilot5)。
        # base-vm イメージから起動し、cloud-init のホスト名をもとに nixos-bootstrap が本構成を自動適用する。
        atelier = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            autopilot5.nixosModules.autopilot5
            ./hosts/base-vm/configuration.nix
            ./modules/common.nix
            ./hosts/atelier/configuration.nix
            {
              networking.hostName = "atelier";
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

        # MVS 3.8j (MVS/CE) を Hercules 上で常駐させるメインフレーム。
        # autoUpgrade で hercules.service が変わると MVS が再起動 (停止 → IPL) されるため、
        # バッチジョブはこの時刻を避けて組む。
        mainframe = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            autoUpgradeSchedule = {
              dates = "04:50";
            };
            # MVS に載せる業務アプリ (mvs-config.nix が書き込む)
            mainframeApps = [
              nuage-usage-ledger.packages.x86_64-linux.default
            ];
            cicerone3270 = cicerone3270.packages.x86_64-linux.default;
          };
          modules = [
            ./hosts/base-lxc/configuration.nix
            ./modules/common.nix
            ./hosts/mainframe/configuration.nix
            sops-nix.nixosModules.sops
            {
              networking.hostName = "mainframe";
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
