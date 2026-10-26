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

  # prvmain (10.20.1.0/24) に足を持たず VIP 10.20.1.20 に届かないため、LAN 側の VIP から journald を送る
  services.journald.upload.settings.Upload.URL = "http://192.168.5.200:8427/insert/journald";

  boot.initrd.kernelModules = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };
}
