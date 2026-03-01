{ modulesPath, pkgs, lib, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../common/configuration.nix
    ./dns.nix
    ./haproxy.nix
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
