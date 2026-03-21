{ pkgs, lib, ... }:

{
  imports = [

  ];

  networking = {
    hostName = "dev-server";
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

}
