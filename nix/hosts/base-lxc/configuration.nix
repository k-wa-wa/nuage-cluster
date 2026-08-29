{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/common.nix
  ];

  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  # NixOS 側で networking.hostName を管理・評価できるようにする
  proxmoxLXC.manageHostName = true;

  systemd.network.wait-online.anyInterface = true;
}
