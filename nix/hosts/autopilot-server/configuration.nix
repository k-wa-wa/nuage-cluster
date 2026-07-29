{ pkgs, lib, ... }:

{
  imports = [
    ./service.nix
    ./devtools.nix
  ];

  networking = {
    hostName = "autopilot-server";
    useDHCP = false;

    # lb の CoreDNS (VIP: 192.168.5.200) を参照する。
    nameservers = [ "192.168.5.200" ];
  };

  # claude / agy 用の nix-ld 設定
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    curl
    icu
    nss
    expat
    fuse3
  ];
}
