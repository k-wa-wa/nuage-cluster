{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    colmena.url = "github:zhaofengli/colmena";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, colmena, nixos-generators, ... }:
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
      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
        };

        lb-1 = {
          deployment = {
            targetHost = "192.168.5.201";
            targetUser = "nixos";
          };
          imports = [
            ./hosts/base-lxc/configuration.nix
            ./hosts/loadbalancer/configuration.nix
          ];
        };
      };

      packages = forAllSystems (system: {
        base-lxc = mkBaseLxc;
        base-vm = mkBaseVm;
      });
    };
}
