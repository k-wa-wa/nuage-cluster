{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # lm-server の llama.cpp 用。新しいモデルアーキテクチャへの追従のため unstable を別途ピン留めする。
    nixpkgs-llama-cpp.url = "github:nixos/nixpkgs/nixos-unstable";

    sops-nix = {
      url = "github:Mic92/sops-nix/3433ea14fbd9e6671d0ff0dd45ed15ee4c156ffa";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # autopilot5 (Orca の窓口エージェントから任された仕事を裏で完走させる autopilot-run と、
    # 全エージェント共通のルール・スキル) を提供する。atelier で使用する。
    autopilot5 = {
      url = "github:k-wa-wa/nuage-autopilot5";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # atelier の nixos ユーザーの環境 (シェル・エディタ・git の設定など) と、エージェントに渡す個人の共通ルールは、
    # Mac と共通の nix-config から読み込む。
    # nix-config を更新したら `nix flake update nix-config --flake ./nix` で取り込む。
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-config = {
      url = "github:k-wa-wa/nix-config";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
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
      sops-nix,
      autopilot5,
      home-manager,
      nix-config,
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

        # エージェントと一緒に開発する作業場 (Orca サーバー + autopilot5)。
        # base-vm イメージから起動し、cloud-init のホスト名をもとに nixos-bootstrap が本構成を自動適用する。
        atelier = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            homeModule = nix-config.homeModules.atelier;
            # 個人の共通ルール (日本語・失敗を隠さない など)。autopilot5 の共通ルールの後ろに足す。
            agentRules = nix-config.lib.agentRules;
          };
          modules = [
            autopilot5.nixosModules.autopilot5
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
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
            mainframeJobMetrics = nuage-usage-ledger.packages.x86_64-linux.mainframe-job-metrics;
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
        spiffe-helper = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/spiffe-helper { };
      });

      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          lib = nixpkgs.lib;
          atelierDefault = self.nixosConfigurations.atelier;
          atelierPreview = atelierDefault.extendModules {
            modules = [
              {
                nuage.atelier.spire.previewPrNumber = 42;
              }
            ];
          };
          atelierTestDefault = atelierDefault.extendModules {
            modules = [
              {
                services.nuage.spiffeHelpers.monitoring-bot-token.outputDir = lib.mkForce "/tmp/spiffe-helper-test";
              }
            ];
          };
          atelierTestPreview = atelierTestDefault.extendModules {
            modules = [
              {
                nuage.atelier.spire.previewPrNumber = 42;
              }
            ];
          };
          execAgent = atelierDefault.config.systemd.services.spire-agent.serviceConfig.ExecStart;
          execPreview =
            atelierPreview.config.systemd.services.spiffe-helper-monitoring-bot-token.serviceConfig.ExecStart;
          prepDefault =
            atelierTestDefault.config.systemd.services.spiffe-helper-monitoring-bot-token.serviceConfig.ExecStartPre;
          prepPreview =
            atelierTestPreview.config.systemd.services.spiffe-helper-monitoring-bot-token.serviceConfig.ExecStartPre;
        in
        {
          spiffe-helper-pkg = self.packages.x86_64-linux.spiffe-helper;
          atelier-spire-regression = pkgs.runCommand "atelier-spire-regression" { } ''
            set -euo pipefail

            # 1. spire-agent.conf に unix と systemd の両 WorkloadAttestor が含まれること
            agent_conf=$(printf '%s\n' "${execAgent}" | awk '{print $NF}')
            grep -q 'WorkloadAttestor "unix"' "$agent_conf"
            grep -q 'WorkloadAttestor "systemd"' "$agent_conf"
            grep -q 'NodeAttestor "sshpop"' "$agent_conf"

            # 2. spiffe-helper が v0.12.4 を参照し、preview 有効時でも本番と preview の両ファイルが定義されること
            case "${execPreview}" in
              *spiffe-helper-0.12.4/bin/spiffe-helper*) ;;
              *) echo "unexpected spiffe-helper binary: ${execPreview}" >&2; exit 1 ;;
            esac
            helper_conf=$(printf '%s\n' "${execPreview}" | awk '{print $NF}')
            grep -q 'jwt_audience = "monitoring-pwa"' "$helper_conf"
            grep -q 'jwt_svid_file_name = "monitoring-pwa.jwt"' "$helper_conf"
            grep -q 'jwt_audience = "monitoring-pwa.nuage-monitoring-stack-pr-42"' "$helper_conf"
            grep -q 'jwt_svid_file_name = "monitoring-pwa-preview.jwt"' "$helper_conf"

            # 3. ExecStartPre が有効な本番 JWT を保持し、不要になった preview JWT や無関係なファイルのみ削除すること
            mkdir -p /tmp/spiffe-helper-test
            printf 'PROD_JWT' > /tmp/spiffe-helper-test/monitoring-pwa.jwt
            printf 'PREV_JWT' > /tmp/spiffe-helper-test/monitoring-pwa-preview.jwt
            printf 'STALE_JWT' > /tmp/spiffe-helper-test/stale.jwt

            ${prepPreview}
            [ "$(cat /tmp/spiffe-helper-test/monitoring-pwa.jwt)" = "PROD_JWT" ]
            [ "$(cat /tmp/spiffe-helper-test/monitoring-pwa-preview.jwt)" = "PREV_JWT" ]
            [ ! -e /tmp/spiffe-helper-test/stale.jwt ]

            ${prepDefault}
            [ "$(cat /tmp/spiffe-helper-test/monitoring-pwa.jwt)" = "PROD_JWT" ]
            [ ! -e /tmp/spiffe-helper-test/monitoring-pwa-preview.jwt ]

            mkdir -p "$out"
            touch "$out/passed"
          '';
        };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
