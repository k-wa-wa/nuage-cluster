

/etc/ssh/ssh_config に以下を追加する
```
Host nix-builder
    HostName 192.168.5.162
    User ubuntu
    IdentityFile /Users/watanabekouhei/workspace/nuage-cluster/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

```bash
nix build ./nix#shared-lb \
  --builders "ssh://nix-builder x86_64-linux" \
  --max-jobs 0 -o ./nix/result
```
