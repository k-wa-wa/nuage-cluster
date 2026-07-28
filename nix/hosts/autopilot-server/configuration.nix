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

  # claude / agy は各 CLI の公式インストーラ (curl | bash) で導入し、TUI でサインインする。
  # インストーラが配布するのは generic Linux 向けの動的リンクバイナリであり、
  # NixOS には /lib64/ld-linux-x86-64.so.2 が無いためそのままでは実行できない。
  # nix-ld がスタブのローダーを用意し、nix-ld.libraries で指定した共有ライブラリを
  # 見つけられるようにすることで、これらのバイナリを実行可能にする。
  # dev-server (hosts/dev-server/vscode.nix) と同じ仕組みである。
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc # libstdc++ / libgcc_s
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

  services.nuage-autopilot = {
    enable = true;
    repositories = [
      "k-wa-wa/pechka"
    ];

    # 導入直後のため定期実行は止めておき、まずは手動で 1 サイクルずつ確認する。
    #   sudo systemctl start nuage-autopilot-pechka.service
    #   journalctl -u nuage-autopilot-pechka -f
    # 挙動に納得できたら true に戻す。
    enableTimer = false;

    # 公式インストーラで導入した claude は ~/.local/bin/claude に置かれ、
    # 実体は ~/.local/share/claude/versions/<version> への symlink である。
    # 自動更新時は symlink の向き先が変わるだけなのでこのパスは安定する。
    extraPathPrefixes = [ "/home/nixos/.local" ];
  };
}
