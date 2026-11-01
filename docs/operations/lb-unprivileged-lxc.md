# lb (lb-1 / lb-2 / lb-3) を非特権 LXC に切り替える手順

lb の 3 台を特権 LXC から非特権 LXC に作り直し、LXC に配る秘密ファイル (`sops-key`・`access-tokens-env`) を `0600` にする。

- 特権 LXC ではコンテナの root がホストの root (UID 0) のままで、sys_admin なども残る。ホストを乗っ取るにはカーネルか LXC のバグが 1 つあれば足りる。非特権ならコンテナの root はホストの UID 100000 になり、2 段のバグが要る。
- 秘密ファイルは `0644` で、コンテナ内の全ユーザーから読めた。

## 変更の中身

| 場所 | 変更 |
| :-- | :-- |
| `terraform/vpc/modules/nix-lxc` | `lxc_config.unprivileged` (既定 `false`) を足した。nesting は残す |
| `terraform/vpc/zone-private-k8s/loadbalancer.tf` | lb-1・lb-2・lb-3 を `unprivileged = true` にした |
| `terraform/pve/hosts-secrets/modules/secrets` | 2 つのファイルを `0600` で置く。持ち主は非特権なら `100000:100000` (コンテナの root)、特権なら `0:0`。権限・持ち主を `triggers_replace` に入れた |
| `terraform/pve/hosts-secrets/main.tf` | lb-1〜3 を `unprivileged = true` にした。lb-2・chaos-monitor・pg-cluster-2 の配り先を退役した nuc-2 から server-2 (`192.168.5.26`) に直した |

NixOS 側 (`nix/`) は変えていない。keepalived の VRRP と VIP の付与、`net.ipv4.ip_nonlocal_bind`、HAProxy・CoreDNS の 1024 未満のポートは、どれもコンテナ自身の network namespace の中の操作で、非特権でも効く。下の確認で実機の動きを確かめる。

## 先に知っておくこと

- **`unprivileged` を変えると LXC は作り直しになる** (bpg provider の `ForceNew`)。rootfs は消える。lb は状態を持たないので、作り直したあとは base イメージから NixOS の lb の構成に自分で戻る (下の「3. 構成が戻るのを待つ」)。
- **作り直しのあいだ、VIP (`10.20.1.20`・`192.168.5.200`) は残りの lb に移る**。keepalived は nopreempt なので、作り直した lb は BACKUP で上がり、VIP を取り返さない。
- **同時に 2 台を落とさない**。1 台ずつ、確認が済んでから次へ進む (lb-1 → 確認 → lb-2 → 確認 → lb-3 → 確認)。
- **hosts-secrets を先に適用する**。非特権のコンテナから読めるよう、持ち主を `100000:100000` にしておく。今の特権のコンテナの root はどの持ち主のファイルでも読めるので、先に変えても止まらない。
- `triggers_replace` が変わるため、hosts-secrets の plan には全 12 ホストの置き直し (`must be replaced`) が出る。中身は同じである。lb は `-target` で 1 台ずつ適用し、残りの 9 台は最後にまとめて適用する (「5. 残りのホストの秘密ファイル」)。
- 作り直した lb の `/var/lib/pve/<name>` (ホスト側) はコンテナと別物なので消えない。PVE のバックアップジョブも同じ VMID のまま残る。

コマンドはリポジトリルートで実行する。terragrunt は state と age 鍵のある手元 (Mac) で実行する。
作り直した直後は base イメージの `nixos` ユーザーしか居ないため、構成が戻るまでは Mac から `ssh` する (atelier の `agent` ユーザーは構成が戻ってから入れる)。

## 0. 事前確認

```bash
export PATH=$HOME/.nix-profile/bin:$PATH
export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

# 3 台とも動いていること
for h in lb-1 lb-2 lb-3; do echo "== $h"; ssh $h 'systemctl is-active keepalived haproxy coredns'; done

# どの lb が VIP を持っているか (以降も使う)
for h in lb-1 lb-2 lb-3; do echo "$h: $(ssh $h 'ip -4 -o addr show | grep -oE "(10\.20\.1\.20|192\.168\.5\.200)/" | tr -d / | tr "\n" " "')"; done
```

全体の plan で、作り直しが lb の 3 台だけであることを確かめる。

```bash
# lb-1〜3 の proxmox_virtual_environment_container.lxc が must be replaced
# (unprivileged = false -> true # forces replacement) で、それ以外の差分が無い
terragrunt --working-dir terraform/vpc/zone-private-k8s plan

# lb 以外の nix-lxc は差分が無い (No changes)
terragrunt --working-dir terraform/vpc/zone-private-persistent plan
terragrunt --working-dir terraform/vpc/zone-private-persistent-fs plan
terragrunt --working-dir terraform/vpc/zone-private-mainframe plan

# 12 ホストすべての terraform_data.upload_file が must be replaced
terragrunt --working-dir terraform/pve/hosts-secrets plan
```

## 1 台ずつの手順

lb-1 で書く。lb-2・lb-3 は表のとおり読み替える。

| lb | PVE ノード | 管理 IP | VMID | prvmain | LAN |
| :-- | :-- | :-- | :-- | :-- | :-- |
| lb-1 | nuc-1 | 192.168.5.21 | 211 | 10.20.1.21 | 192.168.5.201 |
| lb-2 | server-2 | 192.168.5.26 | 212 | 10.20.1.22 | 192.168.5.202 |
| lb-3 | server-1 | 192.168.5.25 | 213 | 10.20.1.23 | 192.168.5.203 |

### 1. 秘密ファイルの権限を変える (hosts-secrets)

```bash
# module.lb-1.terraform_data.upload_file must be replaced だけが出る
terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.lb-1
terragrunt --working-dir terraform/pve/hosts-secrets apply -target=module.lb-1
```

apply の出力の最後に `stat` の結果が出る。次のとおりであること。

```text
600 100000:100000 /var/lib/pve/lb-1/access-tokens-env
600 100000:100000 /var/lib/pve/lb-1/sops-key
```

今の (特権の) lb-1 から読めることを確かめる。

```bash
ssh lb-1 'sudo cat /var/lib/nix-provisioning/sops-key > /dev/null && echo ok'   # ok
```

### 2. LXC を作り直す (vpc)

作り直す lb が VIP を持っていれば、先に手放させる。作り直しでも移るが、先に移しておくと切り替わりを見届けられる。

```bash
ssh lb-1 'sudo systemctl stop keepalived'
for h in lb-1 lb-2 lb-3; do echo "$h: $(ssh $h 'ip -4 -o addr show | grep -oE "(10\.20\.1\.20|192\.168\.5\.200)/" | tr -d / | tr "\n" " "')"; done
# 2 つの VIP が lb-2 か lb-3 に移っていること
```

```bash
# module.lb-1.proxmox_virtual_environment_container.lxc must be replaced
# (unprivileged = false -> true # forces replacement) だけが出る。それ以外が出たら止めて中身を確かめる
terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.lb-1
terragrunt --working-dir terraform/vpc/zone-private-k8s apply -target=module.lb-1
```

PVE ノードの設定を見る (読むだけ)。鍵は hosts-secrets と同じ `.ssh/id_rsa` を使う。

```bash
ssh -i .ssh/id_rsa root@192.168.5.21 'pct config 211 | grep -E "^(unprivileged|features):"'
# features: nesting=1
# unprivileged: 1
```

### 3. 構成が戻るのを待つ

作り直した LXC は base イメージ (`nix/hosts/base-lxc`) で起動し、起動 30 秒後に `nixos-upgrade` が master の flake からホスト名 (`lb-1`) の構成へ切り替える。
成功すると `bootstrap-second-switch` がもう一度 switch し、起動されなかったユニットを拾う (`nix/modules/bootstrap.nix`)。
新しい LXC の立ち上がり方は `.agents/skills/deploy-lxc-middleware` のフェーズ 3・4 と `.agents/skills/modify-nix-host` に従う。

```bash
# 2 回目の switch が終わるまで待つ (最大 10 分)
for i in $(seq 40); do
  ssh lb-1 'test -e /var/lib/bootstrap-second-switch-done && [ "$(systemctl show -p ActiveState --value bootstrap-second-switch)" = inactive ]' 2>/dev/null && break
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
# 600 root:root /var/lib/nix-provisioning/sops-key

# root 以外からは読めない
ssh lb-1 'cat /var/lib/nix-provisioning/sops-key'    # Permission denied
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
dig +short @10.20.1.20 argocd.wpcapp.net                                     # atelier など prvmain から: 10.20.1.20
nc -vz -w 3 10.20.1.20 8427                                                  # atelier など prvmain から: succeeded
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

## 5. 残りのホストの秘密ファイル

lb の 3 台が済んだら、残りの 9 台 (egress-gateway・chaos-monitor・pg-cluster-1〜3・mainframe・swfs-cluster-1〜3) の秘密ファイルを `0600 root:root` で置き直す。
中身は同じで、これらは特権の LXC なので root はそのまま読める。chaos-monitor・pg-cluster-2 は配り先が server-2 に変わる (ディレクトリは nuc-2 からの移行のときに作ってある)。

```bash
# lb-1〜3 は差分が無く、残りの 9 台が must be replaced
terragrunt --working-dir terraform/pve/hosts-secrets plan
terragrunt --working-dir terraform/pve/hosts-secrets apply

ssh egress-gateway 'sudo stat -c "%a %U:%G %n" /var/lib/nix-provisioning/*'    # 600 root:root
```

sops の復号は次の nixos-upgrade (アクティベーション) で行われる。1 台で先に確かめるなら、1 台構成のホストで起動する。

```bash
ssh egress-gateway 'sudo systemctl start nixos-upgrade; journalctl -u nixos-upgrade -n 20 --no-pager -o cat'
```

## 戻し方 (特権に戻して作り直す)

1 台ずつ戻す。lb-1 で書く。

1. `terraform/vpc/zone-private-k8s/loadbalancer.tf` の lb-1 から `unprivileged = true` を外す。`terraform/pve/hosts-secrets/main.tf` の lb-1 からも外す。
2. **vpc を先に適用する**。特権のコンテナの root は持ち主が `100000` でも `0` でも読めるが、非特権のコンテナの root は持ち主が `0` の `0600` のファイルを読めない。hosts-secrets を先に戻すと、残っている非特権のコンテナが鍵を読めなくなる。

   ```bash
   ssh lb-1 'sudo systemctl stop keepalived'     # VIP を先に手放させる
   # module.lb-1.proxmox_virtual_environment_container.lxc must be replaced (unprivileged = true -> false)
   terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.lb-1
   terragrunt --working-dir terraform/vpc/zone-private-k8s apply -target=module.lb-1
   ```

3. 「3. 構成が戻るのを待つ」を行う。
4. hosts-secrets を戻す。`stat` の結果が `600 0:0` になる。

   ```bash
   terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.lb-1
   terragrunt --working-dir terraform/pve/hosts-secrets apply -target=module.lb-1
   ```

5. 「4. 確認」を行う。`uid_map` は `0 0 4294967295` になる。

作り直しの途中で apply が失敗し、LXC が消えたままになったときも、VIP は残りの 2 台が持つ。原因を直して同じ apply をやり直すか、上の手順で特権に戻す。
