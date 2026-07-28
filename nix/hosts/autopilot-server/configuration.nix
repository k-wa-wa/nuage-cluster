{ pkgs, lib, nuage-workspace, ... }:

let
  repositories = [
    "k-wa-wa/pechka"
    "k-wa-wa/nuage-cluster"
    "k-wa-wa/nuage-monitoring-stack"
    "k-wa-wa/bare-web-proxy"
    "k-wa-wa/nuage-workspace"
  ];
  allReposArg = lib.concatStringsSep "," repositories;
  pkg = nuage-workspace.packages.${pkgs.system}.nuage-autopilot;
  repoBaseName = repo: lib.last (lib.splitString "/" repo);
  unitName = repo: "nuage-autopilot-${repoBaseName repo}";

  mkRepoService = repo: {
    name = unitName repo;
    value = {
      description = "nuage-autopilot: ${repo} の 1 サイクルを実行する";

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = [ pkgs.git pkgs.gh "/home/nixos/.local" ];

      environment.NUAGE_STATE_DIR = "/var/lib/nuage-autopilot";

      serviceConfig = {
        Type = "oneshot";

        StateDirectory = "nuage-autopilot";

        EnvironmentFile = "-/var/lib/nuage-autopilot/secrets.env";

        TimeoutStartSec = "30m";

        ExecStart = "${lib.getExe pkg} --repo ${repo} --all-repos ${allReposArg}";

        User = "nixos";
      };
    };
  };
in
{
  networking = {
    hostName = "autopilot-server";
    useDHCP = false;

    # lb の CoreDNS (VIP: 192.168.5.200) を参照する。
    nameservers = [ "192.168.5.200" ];
  };

  # claude / agy 用の nix-ld 設定
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc
    zlib
    openssl
    curl
    icu
    nss
    expat
    fuse3
  ];

  # autopilot が対象リポジトリを clone し、GitHub を操作するために必要なツール。
  environment.systemPackages = with pkgs; [
    git
    gh
    jq
  ];

  systemd.services = lib.listToAttrs (map mkRepoService repositories);
}
