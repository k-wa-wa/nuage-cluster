{ pkgs, lib, ... }:

{
  imports = [
    ./extract.nix
  ];

  environment.systemPackages = with pkgs; [
    usbutils
    lsof
  ];
}
