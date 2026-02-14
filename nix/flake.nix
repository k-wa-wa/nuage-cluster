{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-linux" ];
      
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      mkLxc = hostName: confPath: nixos-generators.nixosGenerate {
        system = "x86_64-linux";
        format = "proxmox-lxc";
        modules = [ confPath ];
      };
    in {
      packages = forAllSystems (system: {
        shared-lb = mkLxc "shared-lb" ./hosts/shared-lb/configuration.nix;
      });
    };
}
