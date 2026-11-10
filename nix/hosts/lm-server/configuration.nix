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

  # SSH のホスト鍵は scripts/gen-host-keys.sh で作り、Terraform の cloud-config (terraform/vpc/zone-private-k8s/lm-server.tf) が置く。
  # 公開鍵は .ssh/known_hosts にある。
  services.openssh.hostKeys = [
    {
      path = "/var/lib/nix-provisioning/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];

  # prvmain (10.20.1.0/24) に足を持たず VIP 10.20.1.20 に届かないため、LAN 側の VIP から journald を送る
  services.journald.upload.settings.Upload.URL = "http://192.168.5.200:8427/insert/journald";

  boot.initrd.kernelModules = [ "amdgpu" ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  system.autoUpgrade.healthCheck.requiredUnits = [
    "llama-cpp.service"
  ];
}
