{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/bootstrap.nix
  ];

  # NixOS 側で networking.hostName を管理・評価できるようにする
  proxmoxLXC.manageHostName = true;

  systemd.network.wait-online.anyInterface = true;
}
