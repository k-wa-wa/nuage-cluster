{ pkgs, lib, ... }:

{
  imports = [
  ];

  # rocm を使用できるようにする
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;

  boot.initrd.kernelModules = [ "amdgpu" ];
  hardware.opengl.enable = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };
}
