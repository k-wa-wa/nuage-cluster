{ pkgs, lib, ... }:

{
  imports = [
    (fetchTarball "https://github.com/nix-community/nixos-vscode-server/tarball/master")
  ];

  services.vscode-server.enable = true;
  # VS Code Remote SSH などの動的バイナリを動かすための設定
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    # VS Code Server や Node.js が必要とする一般的なライブラリ
    stdenv.cc.cc
    zlib
    fuse3
    icu
    nss
    openssl
    curl
    expat
  ];
}
