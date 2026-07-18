#!/usr/bin/env bash

set -euo pipefail

# PATHの優先指定（Nixのパスも含める）
export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

echo "=== Nix Validation ==="

# 1. Nix Flake Check
echo "Running nix flake check..."
nix flake check ./nix

# 2. NixOS Build Dry-run (Linux Only)
if [ "$(uname -s)" = "Linux" ]; then
  echo "Running NixOS configurations dry-run build..."
  hosts=("base-vm" "dev-server" "lb-1" "lb-2" "lb-3" "egress-gateway" "lm-server")
  for host in "${hosts[@]}"; do
    echo "Dry-running build for host: $host"
    nix build ./nix#nixosConfigurations."$host".config.system.build.toplevel --dry-run
  done
else
  echo "Skipping NixOS build dry-run (Not on Linux)"
fi

echo "🎉 All Nix validations passed!"
