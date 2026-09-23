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
}
