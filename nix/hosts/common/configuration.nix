{ ... }:

{
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

  system.stateVersion = "24.11";
}
