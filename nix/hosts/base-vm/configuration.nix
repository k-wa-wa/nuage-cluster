{ modulesPath, pkgs, lib, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/common.nix
  ];

  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  systemd.services.nixos-bootstrap = {
    description = "Bootstrap NixOS configuration from Cloud-Init hostname";
    wantedBy = [ "multi-user.target" ];
    after = [ "cloud-init.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ git nix nixos-rebuild coreutils gnugrep gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # すでにブートストラップ完了している場合はスキップ
      if [ -f /var/lib/nixos-bootstrap-done ]; then
        echo "Bootstrap already completed."
        exit 0
      fi

      CFG_FILE="/var/lib/cloud/instance/cloud-config.txt"
      if [ ! -f "$CFG_FILE" ]; then
        echo "Cloud-init config file not found yet."
        exit 1
      fi

      # cloud-init から渡されたホスト名を取得
      HOSTNAME=$(grep -E "^hostname:" "$CFG_FILE" | awk '{print $2}')
      if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" = "nixos" ]; then
        echo "Valid hostname not found in cloud-init config."
        exit 1
      fi

      echo "Bootstrapping NixOS configuration for hostname: $HOSTNAME"

      # 一時的にホスト名を設定して nixos-rebuild に認識させる
      echo "$HOSTNAME" > /proc/sys/kernel/hostname

      # GitHub から該当するホスト名の構成を取得して適用
      nixos-rebuild switch --flake "github:k-wa-wa/nuage-cluster?dir=nix#$HOSTNAME" --refresh

      if [ $? -eq 0 ]; then
        touch /var/lib/nixos-bootstrap-done
        echo "Bootstrap successfully completed!"
      else
        echo "Bootstrap failed."
        exit 1
      fi
    '';
  };

  # イメージ側のディスクパーティション構造に合わせたマウント定義 (lib.mkDefault で他構成との競合を回避)
  fileSystems."/" = lib.mkDefault {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = [ "x-systemd.growfs" "x-initrd.mount" ];
  };

  fileSystems."/boot" = lib.mkDefault {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
    options = [ "defaults" ];
  };
}
