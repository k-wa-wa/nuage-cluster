{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Base CLI & Search Tools
    git
    gh
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

    # Node.js Environment
    nodejs_22
    corepack

    # Python Environment
    python3
    uv
    ruff

    # Build Tools
    gcc
    gnumake

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
