{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    colmena.url = "github:zhaofengli/colmena";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-ollama.url = "github:nixos/nixpkgs/5b2c2d84341b2afb5647081c1386a80d7a8d8605";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-config = {
      url = "github:k-wa-wa/nix-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, colmena, disko, nixos-generators, nixpkgs-ollama, nixpkgs-unstable, home-manager, nix-config, ... }:
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
        format = "iso"; # terraform (bpg/proxmox) で扱いやすい iso 形式とする
        modules = [
          ./hosts/base-vm/configuration.nix
        ];
      };
    in {
      nixosConfigurations.base-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ./hosts/base-vm/disko-config.nix
          ./hosts/base-vm/configuration.nix
        ];
      };

      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
        };

        dev-server = {
          deployment = {
            targetHost = "192.168.5.199";
            targetUser = "nixos";
            allowLocalDeployment = true;
            tags = [ "dev-server" ];
          };
          imports = [
            home-manager.nixosModules.home-manager
            disko.nixosModules.disko
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

        lb-1 = {
          deployment = {
            targetHost = "192.168.5.201";
            targetUser = "nixos";
            tags = [ "loadbalancer" ];
          };
          imports = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
          ];
        };
        lb-2 = {
          deployment = {
            targetHost = "192.168.5.202";
            targetUser = "nixos";
            tags = [ "loadbalancer" ];
          };
          imports = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
          ];
        };
        lb-3 = {
          deployment = {
            targetHost = "192.168.5.203";
            targetUser = "nixos";
            tags = [ "loadbalancer" ];
          };
          imports = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
          ];
        };

        lm-server = {
          deployment = {
            targetHost = "192.168.5.222";
            targetUser = "nixos";
            tags = [ "lm-server" ];
          };
          imports = [
            disko.nixosModules.disko
            ./hosts/base-vm/disko-config.nix
            ./hosts/base-vm/configuration.nix
            ./hosts/lm-server/configuration.nix
            {
              services.ollama = {
                enable = true;
                # ここで nixpkgs-ollama (特定のコミット) のパッケージを指定
                package = nixpkgs-ollama.legacyPackages.x86_64-linux.ollama-rocm;
                acceleration = "rocm";
                loadModels = [ "qwen3.5:35b-a3b" ];
                host = "0.0.0.0";
                environmentVariables = {
                  OLLAMA_KEEP_ALIVE = "-1";
                  HSA_OVERRIDE_GFX_VERSION = "11.0.0";
                };
                # curl -s http://localhost:11434/api/generate -d '{"model": "qwen3.5:35b-a3b", "keep_alive": -1}'
              };
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
