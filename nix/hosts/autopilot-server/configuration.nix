{ pkgs, ... }:

{
  networking = {
    hostName = "autopilot-server";
    useDHCP = false;

    # lb の CoreDNS (VIP: 192.168.5.200) を参照する。
    # CoreDNS は cluster.wpc をワイルドカードで 192.168.5.200 に解決し、
    # それ以外は 8.8.8.8 へ forward する (nix/hosts/loadbalancer/dns.nix)。
    # preview 環境は PR ごとに pechka-pr-<N>.cluster.wpc という動的な名前になるため、
    # chaos-monitor のような networking.hosts へのハードコードでは対応できない。
    nameservers = [ "192.168.5.200" ];
  };

  # autopilot が対象リポジトリを clone し、GitHub を操作するために必要なツール。
  # LLM CLI 本体はサービスの path 経由で渡す (services.nuage-autopilot.extraPackages)。
  environment.systemPackages = with pkgs; [
    git
    gh
    jq
  ];

  services.nuage-autopilot = {
    enable = true;
    repositories = [
      "k-wa-wa/pechka"
    ];
  };
}
