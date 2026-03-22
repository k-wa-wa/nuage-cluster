
```
nix profile install nixpkgs#colmena


nix build ./nix#base-vm -o ./nix/result

# dev-server
nix run github:numtide/nixos-anywhere -- \
  --flake ./nix#base-vm \
  --target-host nixos@192.168.5.199

colmena apply -f nix/hive.nix --on @dev-server

# lm-server
nix run github:numtide/nixos-anywhere -- \
  --flake ./nix#base-vm \
  --target-host nixos@192.168.5.222

colmena apply -f nix/hive.nix --on @lm-server

# update
nix flake update nix-config --flake ./nix
```
