
/etc/ssh/ssh_config に以下を追加する
```
Host nix-builder
    HostName 192.168.5.162
    User ubuntu
    IdentityFile /Users/watanabekouhei/workspace/nuage-cluster/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

mac

```bash
nix build ./nix#base-lxc \
  --builders "ssh://nix-builder x86_64-linux" \
  --max-jobs 0 -o ./nix/result

nix build ./nix#base-vm \
  --builders "ssh://nix-builder x86_64-linux" \
  --max-jobs 0 -o ./nix/result
```

linux

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
```
