{ modulesPath, pkgs, lib, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../../.ssh/id_ed25519_nixos.pub)
    ];
  };

  security.sudo.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

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

  system.stateVersion = "24.11";
}
