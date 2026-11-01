# egress-gateway と chaos-monitor を非特権 LXC に切り替える手順

egress-gateway と chaos-monitor を特権 LXC から非特権 LXC に作り直し、`/var/lib/nix-provisioning` を読み取り専用にする。
理由・仕組み・確認項目の意味・戻し方の順番は lb のときと同じなので、[2026-11-01-lb-unprivileged-lxc.md](2026-11-01-lb-unprivileged-lxc.md) (以下「lb の手順書」) を参照する。ここには違うところだけを書く。

| LXC | VMID | PVE ノード | 管理 IP | prvmain | LAN | 主なユニット |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| egress-gateway | 220 | server-1 | 192.168.5.25 | 10.20.1.30 | 192.168.5.220 | `haproxy`・`prometheus-node-exporter` |
| chaos-monitor | 250 | server-2 | 192.168.5.26 | 10.20.1.250 | 192.168.5.250 | `prometheus`・`grafana`・`prometheus-blackbox-exporter` |

UID の範囲は lb と同じ `100000:65536` を共有する (コンテナごとに分ける件は #84)。nesting は残す。

## 変更の中身

| 場所 | 変更 |
| :-- | :-- |
| `terraform/vpc/zone-private-k8s/egress-gateway.tf`・`chaos-monitor.tf` | `unprivileged = true`・`provisioning_read_only = true` |
| `terraform/pve/hosts-secrets/main.tf` | egress-gateway・chaos-monitor を `unprivileged = true` (鍵ファイルの持ち主を `100000:100000` にする) |
| `nix/hosts/chaos-monitor/configuration.nix` | `net.ipv4.ping_group_range` を `"0 65535"` にする |

chaos-monitor の blackbox exporter は icmp を ping socket で送っている。CapabilityBoundingSet が空なので CAP_NET_RAW を持てず、raw socket には落ちられない。
ping socket を使えるかは `net.ipv4.ping_group_range` で決まる。NixOS の既定 `"0 2147483647"` は、非特権のコンテナでは GID の写像 (0〜65535) の外を含むためカーネルに `Invalid argument` で弾かれる。値は無効の既定 (`1 0`、中からは `65534 65534` に見える) のまま残り、icmp の監視がすべて失敗する。
写像の中の `"0 65535"` なら書ける。特権の今のコンテナでも書け、blackbox exporter の GID (DynamicUser、61184〜65519) は範囲に入るので、先にマージして適用されても害は無い。

egress-gateway の NixOS は変えない。`net.ipv4.ip_nonlocal_bind`・`net.ipv4.ip_unprivileged_port_start` は netns ごとの値で、非特権でもコンテナの root が書ける。haproxy・node exporter のポート (8080・8404・9100) は 1024 以上である。

## 止まるもの・消えるもの

- **egress-gateway**: 1 台だけなので、作り直しの約 5 分は k8s → lm-server の中継が止まる。litellm の `lm-server/auto` は失敗し、`auto` は sakura に切り替わる。rootfs に状態は無い。
- **chaos-monitor**: 約 5 分、外部監視が止まる。rootfs にある Prometheus の履歴 (`/var/lib/prometheus2`) と Grafana の状態 (`/var/lib/grafana`) は消える (消えてよいことは合意済み)。ダッシュボードとデータソースは nix のプロビジョニングで戻る。
- 作り直した直後は cloud-init で約 4 分 SSH が応答しない (#83)。下のコマンドの `sleep 240` はこのためである。
- egress-gateway → chaos-monitor の順に行う。egress-gateway の作り直し中、chaos-monitor では egress-gateway が down に見えるが、それで正しい。

## 0. 事前確認

**この PR をマージしてから、master を pull した手元 (Mac) で行う。** 作り直した LXC は master の flake から構成を取るので、chaos-monitor の `ping_group_range` が master に入っていないと icmp の監視が失敗する。

```bash
cd ~/ghq/github.com/k-wa-wa/nuage-cluster && git pull

# 今の状態を控える (作り直したあとと比べる)
ssh egress-gateway 'curl -s http://10.20.1.30:8404/metrics | grep "^haproxy_server_status" | grep " 1$"'
# haproxy_server_status{proxy="llama-cpp-out",server="lm-server",state="UP か DOWN"} 1
ssh chaos-monitor "curl -sG 127.0.0.1:9090/api/v1/query --data-urlencode 'query=count by (job) (up)'"
# nixos-node-exporter 7・nixos-haproxy 4・node-ping 14・http-ingress-probe 4・tcp-port-probe 1 (2026-11-01 時点)
```

plan を見る。

```bash
# 2 台の proxmox_virtual_environment_container.lxc が must be replaced
# (unprivileged = false -> true # forces replacement と、
#  /var/lib/nix-provisioning の mount_point の read_only = false -> true)。
# どちらも Plan: 1 to add, 0 to change, 1 to destroy。それ以外が出たら止める
terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.egress-gateway
terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.chaos-monitor

# module.<host>.terraform_data.upload_file の作り直しだけ (1 to add, 0 to change, 1 to destroy)
terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.egress-gateway
terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.chaos-monitor

# 全体では、作り直しがこの 2 台 (と hosts-secrets の 2 つ) だけであること
terragrunt --working-dir terraform/vpc/zone-private-k8s plan
terragrunt --working-dir terraform/pve/hosts-secrets plan
```

base イメージが古くないかの確認 (`terraform/pve/hosts` の plan) は lb の手順書の「0. 事前確認」と同じである。

## 1. 2 台を順に適用する

hosts-secrets → vpc の順に 1 台ずつ適用し、構成が戻ってから次へ進む。途中で失敗すれば止まる。

```bash
cd ~/ghq/github.com/k-wa-wa/nuage-cluster && ssh-add .ssh/keys/pve-root && (
  set -e
  for h in egress-gateway chaos-monitor; do
    echo "===== $h"
    case $h in
      egress-gateway) s="haproxy prometheus-node-exporter" ;;
      chaos-monitor) s="prometheus grafana prometheus-blackbox-exporter" ;;
    esac
    terragrunt --working-dir terraform/pve/hosts-secrets apply -target=module.$h -auto-approve
    terragrunt --working-dir terraform/vpc/zone-private-k8s apply -target=module.$h -auto-approve
    sleep 240
    until ssh -o ConnectTimeout=10 $h 'test -e /var/lib/bootstrap-second-switch-done && [ "$(systemctl show -p ActiveState --value bootstrap-second-switch)" = inactive ] && systemctl is-active -q '"$s"; do sleep 30; done
    ssh $h 'cat /proc/self/uid_map; findmnt -no OPTIONS /var/lib/nix-provisioning; systemctl --failed --no-pager'
  done
)
```

各ホストで `0 100000 65536`・`ro,...`・`0 loaded units listed` が出ればよい。
10 分を過ぎても抜けなければ、Ctrl-C で止めて `ssh $h 'systemctl show -p Result nixos-upgrade bootstrap-second-switch; journalctl -u nixos-upgrade -b -n 20 --no-pager -o cat'` を見る。直し方は lb の手順書の「3. 構成が戻るのを待つ」と同じである。

## 2. 確認

意味は lb の手順書の「4. 確認」と同じである。

```bash
for h in egress-gateway chaos-monitor; do
  echo "===== $h"
  ssh $h 'sudo touch /var/lib/nix-provisioning/access-tokens-env'            # Read-only file system で失敗する
  ssh -o UserKnownHostsFile=.ssh/known_hosts -o StrictHostKeyChecking=yes $h 'echo ok'   # ok (警告もエラーも出ない)
done
```

egress-gateway:

```bash
ssh atelier 'nc -vz -w 3 10.20.1.30 8080; nc -vz -w 3 10.20.1.30 8404'     # どちらも succeeded
ssh egress-gateway 'curl -s http://10.20.1.30:8404/metrics | grep "^haproxy_server_status" | grep " 1$"'   # 事前確認と同じ state
```

chaos-monitor (作り直しで履歴が消えているので、1 分ほど待ってから見る):

```bash
ssh chaos-monitor 'sysctl net.ipv4.ping_group_range'                         # = 0 65535
ssh chaos-monitor 'curl -s "http://127.0.0.1:9115/probe?module=icmp&target=10.20.1.11" | grep "^probe_success"'   # probe_success 1
ssh chaos-monitor "curl -sG 127.0.0.1:9090/api/v1/query --data-urlencode 'query=up == 0'"   # "result":[]
ssh chaos-monitor "curl -sG 127.0.0.1:9090/api/v1/query --data-urlencode 'query=probe_success{job=\"node-ping\"} == 0'"   # "result":[]
ssh chaos-monitor "curl -sG 127.0.0.1:9090/api/v1/query --data-urlencode 'query=count by (job) (up)'"   # 事前確認と同じ数
```

ブラウザで `https://monitoring.wpcapp.net/chaos-monitor/` を開き、ダッシュボードが出ることを見る。

最後に差分が無いことを確かめる。

```bash
terragrunt --working-dir terraform/vpc/zone-private-k8s plan -target=module.egress-gateway -target=module.chaos-monitor   # No changes
terragrunt --working-dir terraform/pve/hosts-secrets plan -target=module.egress-gateway -target=module.chaos-monitor      # No changes
```

## 戻し方

lb の手順書の「戻し方」と同じで、**vpc を先に、hosts-secrets を後に** 1 台ずつ戻す。`lb-1`・`loadbalancer.tf` を `egress-gateway`・`egress-gateway.tf` (または chaos-monitor) に読み替え、keepalived を止める手順は飛ばす。
chaos-monitor の `ping_group_range = "0 65535"` は特権でも書けて blackbox exporter の icmp も通るので、戻すときも残してよい。
