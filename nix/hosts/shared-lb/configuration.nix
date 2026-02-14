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
    interfaces = {
      eth0.ipv4.addresses = [{
        address = "10.10.1.2";
        prefixLength = 24;
      }];
      eth1.ipv4.addresses = [{
        address = "192.168.5.190";
        prefixLength = 24;
      }];
      eth2.ipv4.addresses = [{
        address = "10.0.1.2";
        prefixLength = 24;
      }];
    };
    nameservers = [ "8.8.8.8" ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_nonlocal_bind" = 1;
  };
}
