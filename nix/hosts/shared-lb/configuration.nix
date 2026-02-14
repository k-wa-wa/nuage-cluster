{ modulesPath, pkgs, lib, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../common/configuration.nix
    ./haproxy.nix
  ];

  networking = {
    hostName = "shared-lb";
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "192.168.5.190";
      prefixLength = 24;
    }];
    defaultGateway = {
      address = "192.168.5.1";
      interface = "eth0";
    };
    nameservers = [ "8.8.8.8" ];
  };
}
