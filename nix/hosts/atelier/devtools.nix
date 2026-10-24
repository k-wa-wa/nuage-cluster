# エージェントが各リポジトリをビルド・テストするためのツール。
{ pkgs, ... }:

let
  # ghq でクローンし、Orca に登録する。リポジトリは Mac と同じ ~/ghq/<host>/<owner>/<repo> に置く。
  # Orca のクライアントからサーバーへクローンすると置き場所を毎回手で入力することになるため、これを使う。
  orca-get = pkgs.writeShellApplication {
    name = "orca-get";
    runtimeInputs = with pkgs; [
      ghq
      git
      gh
    ];
    text = ''
      if [ $# -ne 1 ]; then
        echo "usage: orca-get <owner/repo | URL>" >&2
        exit 2
      fi
      ghq get "$1"
      # URL でも owner/repo でも、ghq の置き場所 (host/owner/repo) に揃えて引く。
      name=$(printf '%s' "$1" | sed -E 's#^(https?://|ssh://)?(git@)?##; s#:#/#; s#\.git$##; s#/$##')
      case "$name" in
        */*/*) ;;
        *) name="github.com/$name" ;;
      esac
      path="$(ghq root)/$name"
      [ -d "$path/.git" ] || { echo "クローン先が見つからない: $path" >&2; exit 1; }
      # orca-ide は setup.sh が ~/.local/bin に入れる (nix の外)。
      orca-ide repo add --path "$path"
    '';
  };
in
{
  environment.systemPackages = with pkgs; [
    # Base CLI & Search Tools
    git
    gh
    ghq
    orca-get
    jq
    yq-go
    ripgrep
    fd
    tree
    curl
    wget

    # Go Environment
    go
    gopls
    golangci-lint

    # Node.js / Bun Environment
    nodejs_22
    corepack
    bun

    # Python Environment
    python3
    uv
    ruff

    # Build Tools
    gcc
    gnumake

    # Nix
    nixfmt-tree

    # Infrastructure & Kubernetes Tools
    opentofu
    terragrunt
    kubectl
    kubernetes-helm
    kustomize
    talosctl
    sops
  ];
}
