{ pkgs, lib, ... }:

{
  imports = [
    ./dns.nix
    ./haproxy.nix
    ./keepalived.nix
  ];

  networking = {
    hostName = "shared-lb";
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
  };
}
