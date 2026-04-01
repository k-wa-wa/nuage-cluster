{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/common.nix
  ];
  environment.systemPackages = with pkgs; [
    cloud-init
    ripgrep # 検証
  ];

  services.cloud-init.enable = true;
  services.cloud-init.network.enable = false;
  # systemd.network.networks."10-cloud-init-eth0".enable = false;
}
