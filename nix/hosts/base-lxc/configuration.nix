{ modulesPath, lib, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ../../modules/bootstrap.nix
  ];

  # NixOS 側で networking.hostName を管理・評価できるようにする
  proxmoxLXC.manageHostName = true;

  # テンプレート (tar) の段階ではホスト名が未確定なので空にして /etc/hostname を NixOS に管理させない。
  # 空でないとデフォルト値 "nixos" の /etc/hostname が起動時のアクティベーションで作られ、
  # Proxmox が起動前に書き込んだ本来のホスト名を上書きしてしまい、
  # nixos-upgrade が nixosConfigurations."nixos" を解決しようとして初回 switch に失敗する。
  # 各ホストは flake.nix で networking.hostName を明示しており、そちらが優先される。
  networking.hostName = lib.mkDefault "";

  systemd.network.wait-online.anyInterface = true;

  # SSH のホスト鍵は scripts/gen-host-keys.sh で作り、Terraform (terraform/pve/hosts-secrets) が
  # bind mount の /var/lib/nix-provisioning に置く。公開鍵は .ssh/known_hosts にある。
  # sops-nix もこの鍵を Age 鍵として使う (sops.age.sshKeyPaths の既定値が hostKeys の ed25519 を拾う)。
  # 鍵が無いまま起動すると sshd がその場で作るが、その鍵は .sops.yaml の受信者に無いので、sops-nix の復号が失敗して気づける。
  services.openssh.hostKeys = [
    {
      path = "/var/lib/nix-provisioning/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
}
