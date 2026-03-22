{ pkgs, lib, ... }:

{
  imports = [
    ./vscode.nix
  ];

  networking = {
    hostName = "dev-server";
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  programs.zsh.enable = true;
  users.users.nixos.shell = pkgs.zsh;

  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
  users.users.nixos.extraGroups = [ "docker" ];
}
