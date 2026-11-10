{ pkgs, lib, ... }:

{
  imports = [
    ./haproxy.nix
  ];

  networking = {
    useDHCP = false;
    nameservers = [ "8.8.8.8" ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.ipv4.ip_unprivileged_port_start" = 1000;
  };
}
