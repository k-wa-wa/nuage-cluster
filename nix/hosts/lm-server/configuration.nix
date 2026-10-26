{ pkgs, lib, ... }:

{
  imports = [
    ./llama-cpp.nix
    ./gpu-reboot-once.nix
    ./strata.nix
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

  # 本番推論エンジンとして Strata (Qwen3.8-Flash-Next 125B MoE) を有効化する。
  # 既存の LiteLLM / k8s 連携に影響を与えないよう、ポート 8080 およびモデル名 qwen3.8-27b を引き継ぐ。
  # services.llama-cpp は strata.nix 側で自動的に無効化される。
  services.strata = {
    enable = true;
    port = 8080;
    modelName = "qwen3.8-27b";
  };
}
