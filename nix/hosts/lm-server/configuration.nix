{ pkgs, lib, ... }:

{
  imports = [
    ./llama-cpp.nix
    ./gpu-reboot-once.nix
  ];

  environment.systemPackages = with pkgs; [
    pciutils # lspci を含むパッケージ
    radeontop
  ];

  # rocm を使用できるようにする
  nixpkgs.config.allowUnfree = true;
  hardware.enableAllFirmware = true;

  boot.initrd.kernelModules = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };
}
