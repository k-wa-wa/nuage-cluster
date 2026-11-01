# lb (lb-1 / lb-2 / lb-3) を非特権 LXC に切り替える手順

lb の 3 台を特権 LXC から非特権 LXC に作り直す。
同じ作り直しで、鍵ファイルを置く `/var/lib/nix-provisioning` の bind mount を読み取り専用にする。

- 特権 LXC ではコンテナの root がホストの root (UID 0) と同じである。lb の root を取られると、カーネルか LXC のバグ 1 つで Proxmox ホストに抜けられ、ノード同士の信頼でクラスタ全体に広がる。
- 非特権 LXC ではコンテナの root はホストの UID 100000 に当たり、ホストに抜けても root ではない。
- `/var/lib/nix-provisioning` はホストの `/var/lib/pve/<name>` の bind mount である。書き込み可のままだと、lb の root を取られたときに sshd のホスト鍵 (sops-nix の Age 鍵を兼ねる) や `access-tokens-env` をコンテナの中から書き換えられ、ホスト側の原本が変わる。読み取り専用にすると書き換えられない。

## 変更の中身

| 場所 | 変更 |
| :-- | :-- |
| `terraform/vpc/modules/nix-lxc` | `lxc_config.unprivileged` (既定 `false`) を足した。nesting は残す |
| `terraform/vpc/modules/nix-lxc` | `lxc_config.provisioning_read_only` (既定 `false`) を足した。`true` で `/var/lib/nix-provisioning` の mount_point を `read_only = true` にする。既定の `false` は bpg provider の `read_only` の既定値と同じなので、指定しない LXC は差分が出ない。`var.mount_points` で足す mount_point は変えない |
| `terraform/vpc/zone-private-k8s/loadbalancer.tf` | lb-1・lb-2・lb-3 を `unprivileged = true`・`provisioning_read_only = true` にした |
| `terraform/pve/hosts-secrets/modules/secrets` | `access-tokens-env` と `ssh_host_ed25519_key` の持ち主をコンテナの root にする。`unprivileged = true` なら `100000:100000`、特権なら `0:0`。`0600` は変えない。持ち主は非特権のときだけ `triggers_replace` に入れるので、特権のホストは配り直しにならない |
| `terraform/pve/hosts-secrets/main.tf` | lb-1・lb-2・lb-3 を `unprivileged = true` にした |

`ssh_host_ed25519_key` は sshd のホスト鍵と sops-nix の Age 鍵を兼ねる (`nix/hosts/base-lxc/configuration.nix`)。
持ち主がホストの root (`0:0`) のまま `0600` で非特権にすると、コンテナの root から読めない。sshd が起動できず、sops-nix の復号も失敗し、VRRP のパスワードが無いので keepalived も動かない。

コンテナの中から `/var/lib/nix-provisioning` に書くものは無い。lb-1〜3 の構成で、このパスを使うのは次の 3 つで、どれも読むだけである。

- `nix/modules/common.nix`: nix-daemon の `EnvironmentFile=-/var/lib/nix-provisioning/access-tokens-env`
- `nix/hosts/base-lxc/configuration.nix`: `services.openssh.hostKeys` (sshd の `HostKey`)
- sops-nix: `sops.age.sshKeyPaths` (上のホスト鍵を Age 鍵として読む。`sops.age.generateKey` は `false`)

例外は sshd-keygen である。鍵ファイルが無いか空のときだけ (`ConditionFileNotEmpty=|!`)、`ssh-keygen` で鍵を作ろうとする。読み取り専用ではこれが `Read-only file system` で失敗し、`systemctl --failed` に sshd-keygen が出る。
黙って `.ssh/known_hosts` と sops の受信者に無い鍵を作られるより、失敗して見える方がよい。そのときは hosts-secrets の配り方を確かめる (「1. 秘密ファイルの持ち主を変える」)。

鍵ファイルを置くのはホスト側の hosts-secrets (`terraform/pve/hosts-secrets`) で、PVE ノードの `/var/lib/pve/<name>` に直接書く。コンテナの mount が読み取り専用でも配り直しはできる。

NixOS 側 (`nix/`) は変えていない。keepalived の VRRP と VIP の付与、`net.ipv4.ip_nonlocal_bind`、HAProxy・CoreDNS の 1024 未満のポートは、どれもコンテナ自身の network namespace の中の操作で、非特権でも効く。
lb-1〜3 の `proxmoxLXC.privileged` は既定の `false` で、NixOS は元から非特権を前提にしている。下の確認で実機の動きを確かめる。

## 先に知っておくこと

- **`unprivileged` を変えると LXC は作り直しになる** (bpg provider の `ForceNew`)。`mount_point` も `ForceNew` なので、`read_only` も同じ作り直しで入る。作り直しは 1 回で、`1 to add, 0 to change, 1 to destroy` になる。rootfs は消える。lb は状態を持たないので、作り直したあとは base イメージから NixOS の lb の構成に自分で戻る (下の「3. 構成が戻るのを待つ」)。
- **作り直しのあいだ、VIP (`10.20.1.20`・`192.168.5.200`) は残りの lb に移る**。keepalived は nopreempt なので、作り直した lb は BACKUP で上がり、VIP を取り返さない。
- **同時に 2 台を落とさない**。1 台ずつ、確認が済んでから次へ進む (lb-1 → 確認 → lb-2 → 確認 → lb-3 → 確認)。
- **hosts-secrets を先に適用する**。非特権のコンテナから読めるよう、持ち主を `100000:100000` にしておく。今の特権のコンテナの root はどの持ち主のファイルでも読めるので、先に変えても止まらない。
- 作り直した lb の `/var/lib/pve/<name>` (ホスト側) はコンテナと別物なので消えない。PVE のバックアップジョブも同じ VMID のまま残る。

コマンドはリポジトリルートで実行する。terragrunt は state と age 鍵のある手元 (Mac) で実行する。
作り直した直後は base イメージの `nixos` ユーザーしか居ないため、構成が戻るまでは Mac から `ssh` する (atelier の `agent` ユーザーは構成が戻ってから入れる)。
Mac から pg-cluster・swfs-cluster・mainframe・autopilot-server へは `.ssh/ssh_config` の `ProxyJump lb-1` で入る。
**lb-1 を作り直して構成が戻るまでは、Mac からこれらのホストに入れない。** そのあいだに入る必要があれば、ProxyJump を使わない atelier から入る (`ssh atelier` のあと `ssh pg-cluster-1`)。

## 0. 事前確認

```bash
export PATH=$HOME/.nix-profile/bin:$PATH
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

# 3 台とも動いていること
for h in lb-1 lb-2 lb-3; do echo "== $h"; ssh $h 'systemctl is-active keepalived haproxy coredns'; done

# どの lb が VIP を持っているか (以降も使う)
for h in lb-1 lb-2 lb-3; do echo "$h: $(ssh $h 'ip -4 -o addr show | grep -oE "(10\.20\.1\.20|192\.168\.5\.200)/" | tr -d / | tr "\n" " "')"; done
```

全体の plan で、作り直しと配り直しが lb の 3 台だけであることを確かめる。

```bash
# lb-1〜3 の proxmox_virtual_environment_container.lxc が must be replaced
# (unprivileged = false -> true # forces replacement と、
#  /var/lib/nix-provisioning の mount_point の read_only = false -> true) で、lb のほかに差分が無い。
# lm_server と local_file.talosconfig の差分は今回と関係ないので、apply は下の -target で lb だけに絞る
terragrunt --working-dir terraform/vpc/zone-private-k8s plan

# lb 以外の nix-lxc は差分が無い (No changes)
terragrunt --working-dir terraform/vpc/zone-private-persistent-fs plan
terragrunt --working-dir terraform/vpc/zone-private-mainframe plan

# lb-1〜3 の terraform_data.upload_file だけが must be replaced で、残りの 9 台は差分が無い
terragrunt --working-dir terraform/pve/hosts-secrets plan
```

`zone-private-persistent` の plan には pg-cluster-2 の作り直しが出ることがある。定義の `node_name` が `nuc-2` のままで、実物 (server-2) とずれているためで、今回の変更とは関係ない。
**`zone-private-persistent` では apply しない** (pg-cluster-2 が作り直される)。ずれは別の作業で直す。

```bash
# pg-cluster-2 以外の差分が無いことだけを見る。apply はしない
terragrunt --working-dir terraform/vpc/zone-private-persistent plan
```

作り直した LXC は PVE ノードに置いた base イメージ (`local:vztmpl/nixos-base-lxc.tar.xz`) で起動する。
置いてあるイメージが古いと、構成が戻るまで今の `nixos` の鍵 (`.ssh/keys/nixos`) で入れないことがある (構成が戻れば入れる)。
`terraform/pve/hosts` の plan で `proxmox_download_file.nixos_base_lxc` に差分が出ていれば、先にその apply を済ませておく。

```bash
# proxmox_download_file.nixos_base_lxc["nuc-1"]・["server-1"]・["server-2"] に差分が無いこと
terragrunt --working-dir terraform/pve/hosts plan
```

## 1 台ずつの手順

lb-1 で書く。lb-2・lb-3 は表のとおり読み替える。

| lb | PVE ノード | 管理 IP | VMID | prvmain | LAN |
| :-- | :-- | :-- | :-- | :-- | :-- |
| lb-1 | nuc-1 | 192.168.5.21 | 211 | 10.20.1.21 | 192.168.5.201 |
| lb-2 | server-2 | 192.168.5.26 | 212 | 10.20.1.22 | 192.168.5.202 |
| lb-3 | server-1 | 192.168.5.25 | 213 | 10.20.1.23 | 192.168.5.203 |

### 1. 秘密ファイルの持ち主を変える (hosts-secrets)

hosts-secrets の apply は PVE ノードの root に ssh-agent の鍵で入る。先に `.ssh/keys/pve-root` を agent に載せておく (`terraform/pve/hosts-secrets/modules/secrets/main.tf`)。

```bash
ssh-add .ssh/keys/pve-root

# module.lb-1.terraform_data.upload_file must be replaced だけが出る
terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.lb-1
terragrunt --working-dir terraform/pve/hosts-secrets apply -target=module.lb-1
```

apply の出力の最後に `stat` の結果が出る。次のとおりであること。

```text
600 100000:100000 access-tokens-env
600 100000:100000 ssh_host_ed25519_key
```

今の (特権の) lb-1 から読めることを確かめる。

```bash
ssh lb-1 'sudo cat /var/lib/nix-provisioning/ssh_host_ed25519_key > /dev/null && echo ok'   # ok
```

### 2. LXC を作り直す (vpc)

作り直す lb が VIP を持っていれば、先に手放させる。作り直しでも移るが、先に移しておくと切り替わりを見届けられる。

```bash
ssh lb-1 'sudo systemctl stop keepalived'
for h in lb-1 lb-2 lb-3; do echo "$h: $(ssh $h 'ip -4 -o addr show | grep -oE "(10\.20\.1\.20|192\.168\.5\.200)/" | tr -d / | tr "\n" " "')"; done
# 2 つの VIP が lb-2 か lb-3 に移っていること
```

```bash
# module.lb-1.proxmox_virtual_environment_container.lxc must be replaced だけが出る
# (unprivileged = false -> true # forces replacement と、/var/lib/nix-provisioning の mount_point の
#  read_only = false -> true)。Plan: 1 to add, 0 to change, 1 to destroy。それ以外が出たら止めて中身を確かめる
terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.lb-1
terragrunt --working-dir terraform/vpc/zone-private-k8s apply -target=module.lb-1
```

PVE ノードの設定を見る (読むだけ)。鍵は hosts-secrets と同じ `.ssh/keys/pve-root` を使う。

```bash
ssh -i .ssh/keys/pve-root root@192.168.5.21 'pct config 211 | grep -E "^(unprivileged|features|mp[0-9]+):"'
# features: nesting=1
# mp0: /var/lib/pve/lb-1,mp=/var/lib/nix-provisioning,...,ro=1   (ro=1 が入っていること)
# unprivileged: 1
```

### 3. 構成が戻るのを待つ

作り直した LXC は base イメージ (`nix/hosts/base-lxc`) で起動し、起動 30 秒後に `nixos-upgrade` が master の flake からホスト名 (`lb-1`) の構成へ切り替える。
成功すると `bootstrap-second-switch` がもう一度 switch し、起動されなかったユニットを拾う (`nix/modules/bootstrap.nix`)。
新しい LXC の立ち上がり方は `.agents/skills/deploy-lxc-middleware` のフェーズ 3・4 と `.agents/skills/modify-nix-host` に従う。

```bash
# 2 回目の switch が終わるか、nixos-upgrade が失敗するまで待つ (最大 10 分)
for i in $(seq 40); do
  ssh lb-1 'test -e /var/lib/bootstrap-second-switch-done && [ "$(systemctl show -p ActiveState --value bootstrap-second-switch)" != activating ]' 2>/dev/null && break
  ssh lb-1 '[ "$(systemctl show -p ActiveState --value nixos-upgrade)" = failed ]' 2>/dev/null && break
  sleep 15
done
ssh lb-1 'systemctl show -p Result nixos-upgrade bootstrap-second-switch; journalctl -u nixos-upgrade -b -n 20 --no-pager -o cat'
# Result=success が 2 つ並ぶ
```

`nixos-upgrade` が失敗していれば、原因を直してからもう一度起動する。終わるまで待ち、失敗すればエラーで返る。

```bash
ssh lb-1 'sudo systemctl start nixos-upgrade; journalctl -u nixos-upgrade -n 20 --no-pager -o cat'
```

switch は成功したのにユニットが `inactive (dead)` のままなら、`multi-user.target` を起動して拾う (`modify-nix-host` の既知の罠)。

```bash
ssh lb-1 'sudo systemctl start multi-user.target'
```

### 4. 確認

#### 非特権になったこと・秘密ファイル

```bash
ssh lb-1 'cat /proc/self/uid_map'
#          0     100000      65536

ssh lb-1 'sudo stat -c "%a %U:%G %n" /var/lib/nix-provisioning /var/lib/nix-provisioning/*'
# 755 nobody:nogroup /var/lib/nix-provisioning   (ディレクトリはホストの root のもので、コンテナからは nobody に見える)
# 600 root:root /var/lib/nix-provisioning/access-tokens-env
# 600 root:root /var/lib/nix-provisioning/ssh_host_ed25519_key

# root 以外からは読めない
ssh lb-1 'cat /var/lib/nix-provisioning/ssh_host_ed25519_key'    # Permission denied
```

#### 読み取り専用であること

```bash
ssh lb-1 'findmnt -no OPTIONS /var/lib/nix-provisioning'          # 先頭に ro が出る (ro,relatime,...)
ssh lb-1 'sudo touch /var/lib/nix-provisioning/x'                 # touch: ... Read-only file system で失敗する
ssh lb-1 'ls /var/lib/nix-provisioning'                           # access-tokens-env と ssh_host_ed25519_key だけ (x が無い)
ssh lb-1 'systemctl is-active sshd-keygen; systemctl show -p Result sshd-keygen'   # inactive・Result=success (鍵があるので走らない)
```

`touch` が成功したら読み取り専用になっていない。`ssh lb-1 'sudo rm /var/lib/nix-provisioning/x'` で消し、plan と `pct config` の `ro=1` を確かめる。

#### sshd のホスト鍵

`.ssh/ssh_config` は known_hosts を `/dev/null` にしているので、普段の `ssh` では鍵が違っても警告が出ない。
ここでは `.ssh/known_hosts` を明示して確かめる。

```bash
# 警告もエラーも出ずに ok が出る (sshd がその場で作った鍵で起動していれば Host key verification failed になる)
ssh -o UserKnownHostsFile=.ssh/known_hosts -o StrictHostKeyChecking=yes lb-1 'echo ok'

ssh lb-1 'sudo sshd -T | grep -i "^hostkey "'    # hostkey /var/lib/nix-provisioning/ssh_host_ed25519_key
ssh lb-1 'journalctl -u sshd -b --no-pager -o cat | grep -iE "host key|error" | tail -n 5'   # 鍵を読めないエラーが無い
```

#### sops の復号

```bash
ssh lb-1 'sudo test -s /run/secrets/keepalived_auth_pass && sudo test -s /run/secrets-rendered/keepalived-auth.conf && echo ok'   # ok
ssh lb-1 'journalctl -b --no-pager -o cat | grep -i "sops-install-secrets" | tail -n 5'   # エラーが無い
```

#### サービス

```bash
ssh lb-1 'systemctl is-active keepalived haproxy coredns firewall prometheus-node-exporter systemd-journal-upload'   # すべて active
ssh lb-1 'systemctl --failed --no-pager'                                     # 0 loaded units listed
ssh lb-1 'sysctl net.ipv4.ip_nonlocal_bind'                                  # = 1
ssh lb-1 'journalctl -u keepalived -b -n 20 --no-pager -o cat'               # VI_1・VI_2 とも Entering BACKUP STATE
ssh lb-1 'journalctl -u systemd-journal-upload -b -n 5 --no-pager -o cat'    # 送信のエラーが続いていない
```

#### lb-1 自身の IP で中継が通ること (VIP を動かす前)

HAProxy と CoreDNS はすべてのアドレスで待ち受けるので、VIP を寄せる前に lb-1 自身の IP で確かめる。

```bash
for p in 80 443 6443 3270 8427; do nc -vz -w 3 192.168.5.201 $p; done      # すべて succeeded
dig +short @192.168.5.201 argocd.wpcapp.net                                  # Mac から: 192.168.5.200
curl -sk -o /dev/null -w '%{http_code}\n' --resolve argocd.wpcapp.net:443:192.168.5.201 https://argocd.wpcapp.net/   # 000 以外
```

#### VIP を寄せたときに通ること

keepalived は全台が同じ優先度の BACKUP で nopreempt のため、持ち主が止まると残りの中で IP の大きい方が VIP を取る (lb-3 > lb-2 > lb-1)。
lb-1 に寄せるには、lb-1 以外の 2 台の keepalived を止める。
**このあいだ VIP を持てるのは lb-1 だけになる。上の確認がすべて通ってから行い、確認が済んだらすぐに keepalived を戻す。**

```bash
for h in lb-2 lb-3; do ssh $h 'sudo systemctl stop keepalived'; done
sleep 5
for h in lb-1 lb-2 lb-3; do echo "$h: $(ssh $h 'ip -4 -o addr show | grep -oE "(10\.20\.1\.20|192\.168\.5\.200)/" | tr -d / | tr "\n" " "')"; done
# lb-1: 10.20.1.20 192.168.5.200
```

VIP 経由で確かめる。

```bash
kubectl get nodes                                                            # 6 台 Ready
curl -s  -o /dev/null -w '%{http_code}\n' --resolve argocd.wpcapp.net:80:192.168.5.200  http://argocd.wpcapp.net/    # 000 以外
curl -sk -o /dev/null -w '%{http_code}\n' --resolve argocd.wpcapp.net:443:192.168.5.200 https://argocd.wpcapp.net/   # 000 以外
nc -vz -w 3 192.168.5.200 3270                                               # succeeded (TN3270)
dig +short @192.168.5.200 argocd.wpcapp.net                                  # Mac から: 192.168.5.200
# SDN 側の VIP (10.20.1.20) は Mac から届かないので、prvmain に足のある atelier から確かめる
ssh atelier 'dig +short @10.20.1.20 argocd.wpcapp.net'                       # 10.20.1.20
ssh atelier 'nc -vz -w 3 10.20.1.20 8427'                                    # succeeded
ssh pg-cluster-1 'journalctl -u systemd-journal-upload -n 5 --no-pager -o cat'   # VIP:8427 への送信のエラーが出ていない
```

ブラウザでも `https://argocd.wpcapp.net` などが開くことを見る。

止めた keepalived を戻す。戻した lb は BACKUP で上がり、VIP は lb-1 に残る。

```bash
for h in lb-2 lb-3; do ssh $h 'sudo systemctl start keepalived'; done
for h in lb-1 lb-2 lb-3; do echo "== $h"; ssh $h 'systemctl is-active keepalived haproxy coredns'; done
```

ここまで通ったら、lb-2 (server-2・`192.168.5.26`・VMID 212)、lb-3 (server-1・`192.168.5.25`・VMID 213) の順に 1. から繰り返す。
lb-2・lb-3 で VIP を寄せるときは、止める相手を「その lb 以外の 2 台」に読み替える。

3 台が済んだら、全体の plan に差分が無いことを確かめる。

```bash
terragrunt --working-dir terraform/vpc/zone-private-k8s plan    # No changes
terragrunt --working-dir terraform/pve/hosts-secrets plan       # No changes
```

## 戻し方 (特権に戻して作り直す)

1 台ずつ戻す。lb-1 で書く。戻したことはコードの変更として PR に残す。

1. `terraform/vpc/zone-private-k8s/loadbalancer.tf` の lb-1 から `unprivileged = true` を外す。`terraform/pve/hosts-secrets/main.tf` の lb-1 からも外す。
   `provisioning_read_only = true` は残す。特権のコンテナでも `/var/lib/nix-provisioning` は読むだけで動き、非特権をやめる理由 (keepalived などが動かない) とは関係ないためである。
   ただし特権のコンテナの root は、読み取り専用の mount を書き込み可に付け直せる場合がある (非特権では、ホストが作った mount の読み取り専用はコンテナの中から外せない)。特権に戻しているあいだは、誤って書き換えるのを防ぐ程度の守りになる。
   読み取り専用そのものが原因で戻すとき (コンテナの中から書く必要が出たとき) だけ、`provisioning_read_only = true` も外す。どちらを外しても mount_point の作り直しは同じ 1 回で済む。
2. **vpc を先に適用する**。特権のコンテナの root は持ち主が `100000` でも `0` でも読めるが、非特権のコンテナの root は持ち主が `0` の `0600` のファイルを読めない。hosts-secrets を先に戻すと、残っている非特権のコンテナが鍵を読めなくなる。

   ```bash
   ssh lb-1 'sudo systemctl stop keepalived'     # VIP を先に手放させる
   # module.lb-1.proxmox_virtual_environment_container.lxc must be replaced (unprivileged = true -> false)
   # provisioning_read_only を残したなら read_only の差分は出ない。Plan: 1 to add, 0 to change, 1 to destroy
   terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.lb-1
   terragrunt --working-dir terraform/vpc/zone-private-k8s apply -target=module.lb-1
   ```

3. 「3. 構成が戻るのを待つ」を行う。
4. hosts-secrets を戻す。`stat` の結果が `600 0:0` になる。

   ```bash
   ssh-add .ssh/keys/pve-root
   terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.lb-1
   terragrunt --working-dir terraform/pve/hosts-secrets apply -target=module.lb-1
   ```

5. 「4. 確認」を行う。`uid_map` は `0 0 4294967295` になり、`/var/lib/nix-provisioning` は `nobody:nogroup` ではなく `root:root` に見える。
   `provisioning_read_only = true` を残したなら、「読み取り専用であること」も同じ結果になる。

作り直しの途中で apply が失敗し、LXC が消えたままになったときも、VIP は残りの 2 台が持つ。原因を直して同じ apply をやり直すか、上の手順で特権に戻す。
