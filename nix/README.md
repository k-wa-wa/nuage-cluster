

```
nix profile install nixpkgs#colmena

nix build ./nix#base-lxc -o ./nix/result
colmena apply -f nix/hive.nix
```
