{ modulesPath, ... }:

{
  nix.settings = {
    # 1. リモートからビルド済みのパスを送り込めるようにする
    # root と、デプロイ時に使用するユーザー（nixosなど）を必ず入れる
    trusted-users = [ "root" "nixos" "@wheel" ];

    # 2. 最初の一歩（初回デプロイ）で署名エラーを出さないための設定
    # これを true にしておくと、署名チェックをバイパスして受け入れます
    trusted-public-keys = [ ];
    substituters = [ "https://cache.nixos.org" ];
  };

  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../../../.ssh/id_ed25519_nixos.pub)
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

  system.stateVersion = "24.11";
}
