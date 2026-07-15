{ pkgs, ... }:

{
  nix.settings = {
    trusted-users = [ "root" "nixos" "@wheel" ];

    trusted-public-keys = [ ];
    substituters = [ "https://cache.nixos.org" ];
    experimental-features = [ "nix-command" "flakes" ];
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIi6KgfT6hU8CWl7Xm7bnKen80++7lHrQ+OqvEuAe+80 nixos-sever"
    ];
  };

  security.sudo.enable = true;
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  networking = {
    useDHCP = false;
  };

  environment.systemPackages = [ pkgs.git ];

  system.autoUpgrade = {
    enable = true;
    flake = "https://github.com/k-wa-wa/nuage-cluster/archive/master.tar.gz?dir=nix";
    dates = "daily";
  };

  systemd.timers.nixos-upgrade.timerConfig = {
    OnBootSec = "30s";
  };

  # nix-daemon がトークンファイルを読み込む (ファイルが存在しない場合はエラーにならない)
  systemd.services.nix-daemon.serviceConfig.EnvironmentFile = "-/var/lib/nix-provisioning/access-tokens-env";

  system.stateVersion = "24.11";
}
