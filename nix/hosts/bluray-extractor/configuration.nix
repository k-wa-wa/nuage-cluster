{ pkgs, lib, ... }:

{
  imports = [
    ./extract.nix
  ];

  environment.systemPackages = with pkgs; [
    usbutils
    lsof
  ];

  # SSH のホスト鍵は scripts/gen-host-keys.sh で作り、Terraform の cloud-config (terraform/vpc/zone-private-k8s/bluray-extractor.tf) が置く。
  # 公開鍵は .ssh/known_hosts にある。sops-nix もこの鍵を Age 鍵として使う (sops.age.sshKeyPaths の既定値が hostKeys の ed25519 を拾う)。
  services.openssh.hostKeys = [
    {
      path = "/var/lib/nix-provisioning/ssh_host_ed25519_key";
      type = "ed25519";
    }
  ];
}
