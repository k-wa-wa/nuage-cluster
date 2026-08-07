{ pkgs, lib, unstablePkgs, ... }:

let
  # facefusion (conda/pip 導入) の MIGraphX Execution Provider が要求する ROCm ランタイムは
  # nixpkgs-unstable の glibc (2.42) でビルドされている。nix-ld はローダを常にホストの
  # nixos-24.11 系 glibc (2.40) から取るため世代差で GLIBC_ABI_GNU2_TLS 等のシンボルが解決できず
  # EP のロードに失敗する (nix-ld.nix の `pkgs.stdenv.cc.bintools.dynamicLinker` はホスト pkgs 固定で
  # programs.nix-ld.package では変更できない)。
  # buildFHSEnv でローダも ROCm ライブラリもすべて unstablePkgs に統一したサンドボックスを用意し、
  # facefusion はこの中で実行する。
  #   facefusion-env -c 'source ~/miniconda3/etc/profile.d/conda.sh && conda activate facefusion && cd ~/facefusion && python facefusion.py run --open-browser'
  facefusionEnv = unstablePkgs.buildFHSEnv {
    name = "facefusion-env";
    targetPkgs = p: with p; [
      stdenv.cc.cc
      zlib
      git
      curl
      ffmpeg
      rocmPackages.clr
      rocmPackages.hipblas
      rocmPackages.rocblas
      rocmPackages.miopen
      rocmPackages.migraphx
    ];
    runScript = "bash";
  };
in

{
  imports = [
  ];

  environment.systemPackages = with pkgs; [
    pciutils  # lspci を含むパッケージ
    radeontop
    rocmPackages.rocminfo
    rocmPackages.rocm-smi
    ffmpeg
    facefusionEnv
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

  networking.firewall.allowedTCPPorts = [ 11434 ];
  # facefusion の Web UI (Gradio, デフォルト 7860) は既定で localhost bind のため、
  # LAN 公開はせず `ssh -L 7860:localhost:7860 lm-server` でのトンネル経由アクセスを前提とする。

  # lm-server は物理メモリ 7.8GiB のみで swap が存在しない。MIGraphX は未サポート GPU
  # (gfx1102 を gfx1100 として override) 向けの自動チューニングでモデルごとに数GB のメモリを
  # 消費し、swap が無いと OOM Killer に殺される (実際に facefusion のモデルコンパイル中に発生した)。
  swapDevices = [
    { device = "/var/lib/swapfile"; size = 6 * 1024; }
  ];
}
