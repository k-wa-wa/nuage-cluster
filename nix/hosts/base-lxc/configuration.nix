{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/common.nix
  ];

  services.cloud-init.enable = true;
  # services.cloud-init.network.enable = true;
  # systemd.network.networks."10-cloud-init-eth0".enable = false;
}
