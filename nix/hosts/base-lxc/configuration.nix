{ modulesPath, pkgs, lib, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/common.nix
  ];

  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  systemd.network.wait-online.anyInterface = true;

  environment.systemPackages = [ pkgs.git ];

  system.autoUpgrade = {
    enable = true;
    flake = "git+https://github.com/k-wa-wa/nuage-cluster.git?dir=nix";
    dates = "hourly";
    flags = [
      "--update-input"
      "nixpkgs"
      "-L"
    ];
  };
}
