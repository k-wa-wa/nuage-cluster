{ modulesPath, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../base-common/configuration.nix
  ];

  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;
}
