
```
nix profile install nixpkgs#colmena

# loadbalancer
colmena apply -f nix/hive.nix --on @loadbalancer

# dev-server
nix run github:numtide/nixos-anywhere -- \
  --flake ./nix#base-vm \
  --target-host nixos@192.168.5.199

colmena apply -f nix/hive.nix --on @dev-server
sudo colmena apply-local -f nix/hive.nix --node dev-server

# lm-server
nix run github:numtide/nixos-anywhere -- \
  --flake ./nix#base-vm \
  --target-host nixos@192.168.5.222

colmena apply -f nix/hive.nix --on @lm-server

# update
nix flake update nix-config --flake ./nix
```
