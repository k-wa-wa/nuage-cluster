# keepalived の VRRP のパスワードを止めずに作り直した記録

lb・pg・swfs の 3 クラスタで、keepalived の `keepalived_auth_pass` を作り直した (PR #92)。VIP は一度も動かず、ダウンタイムは無かった。
あわせて、bluray-extractor の秘密から、使っていない `pechka_minio_url` を消し、秘密でない `pechka_minio_bucket` を外して `extract.nix` に直書きした。

作り直した理由は、これらの値を以前 `lb_key` でも暗号化していたことにある。`lb_key` は 2026-11-01 に `.sops.yaml` から外した (`c587aef`)。それでも git の履歴の古い暗号文は、`lb_key` の写しがあれば読める。
残りの値は #97〜#102 で扱う。ここに書いたやり方と注意は、そちらでも使える。

## 変えたもの

| ファイル | 変更 |
| :-- | :-- |
| `nix/hosts/loadbalancer/secrets.yaml`・`postgres-cluster/secrets.yaml`・`swfs-cluster/secrets.yaml` | `keepalived_auth_pass` を新しい値にする (クラスタごとに別の値、8 文字) |
| `nix/hosts/bluray-extractor/secrets.yaml` | `pechka_minio_url`・`pechka_minio_bucket` を消す |
| `nix/hosts/bluray-extractor/extract.nix` | `MINIO_BUCKET="pechka"` を直書きする (pechka の `k8s/base/infra/configmap/configmap.yaml` の `minio-bucket` と同じ) |

- keepalived の `auth_type PASS` は、パスワードを 8 文字までしか見ないので 8 文字にした。
- `PASS` は VRRP の合図にパスワードを平文で載せる。同じネットワークにいれば読めるので、守れるのは「設定の違う keepalived を誤って混ぜない」程度である。
- `pg_pechka_username` も秘密ではないが、外すと Patroni のユニットが変わり、nixos-upgrade で Patroni が再起動する。#101 で一緒に扱う。

## SOPS の書き換え (人間が Mac で行った)

`sops set` と `sops unset` で、対象の値だけを変えた。PR の差分は、変えた値の行と `mac`・`lastmodified` だけである。

```bash
(
  set -euo pipefail
  umask 077
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  # バケット名が extract.nix に直書きした値と同じでなければ、何も変えずに止める
  b=$(sops decrypt --extract '["pechka_minio_bucket"]' nix/hosts/bluray-extractor/secrets.yaml)
  [ "$b" = "pechka" ] || { echo "バケット名が pechka ではない: $b"; exit 1; }
  sops unset nix/hosts/bluray-extractor/secrets.yaml '["pechka_minio_url"]'
  sops unset nix/hosts/bluray-extractor/secrets.yaml '["pechka_minio_bucket"]'
  for f in nix/hosts/loadbalancer/secrets.yaml nix/hosts/postgres-cluster/secrets.yaml nix/hosts/swfs-cluster/secrets.yaml; do
    v=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | cut -c1-8)
    [ ${#v} -eq 8 ] || { echo "値が 8 文字にならない"; exit 1; }
    printf '%s' "$v" | jq -Rs . > "$TMP/v.json"
    sops set --value-file "$f" '["keepalived_auth_pass"]' "$TMP/v.json"
  done
)
```

## 止めずに反映する考え方

- **sops-nix は、値が変わってもサービスを再起動しない** (`restartUnits` を付けていない)。nixos-upgrade で認証のファイル (`/run/secrets/rendered/keepalived-auth.conf`) は新しい値になるが、keepalived は古い値のまま動き続ける。
- **3 台の `systemctl reload keepalived` を同時に打つ。** reload では VIP は外れない。
  - keepalived は、相手の合図が 3 秒ほど届かないと相手がいないと判断する (`advert_int 1`)。3 台が 1 秒以内に新しい値へそろえば、その判断は起きない。
  - 予備の 2 台を止めてから VIP を持つ 1 台を変えるやり方は使えなかった。pg は primary 用 (`10.20.1.40`) と replica 用 (`10.20.1.50`) の VIP が別のホストにあるからである。
- **反映から reload までの間を空けない。** その間にたまたま keepalived が再起動すると、そのホストだけが新しい値になる。
- **反映の前に、サービスが勝手に再起動しないことを確かめた。**
  - 9 台の `/run/current-system` が、今の master のビルドと同じだった。今回の差は秘密だけである。
  - keepalived・patroni・swfs-s3 のユニットが PR で変わらないことも確かめた。`nix eval --raw ./nix#nixosConfigurations.<host>.config.systemd.units."<unit>.service".unit` を master と PR で比べた。
- 進める順番は、止まったときの影響が小さい順に swfs → pg → lb とした (lb は DNS と外からの入口)。

## 手順 (クラスタごと)

1 台ずつ nixos-upgrade し、keepalived の起動時刻が変わらないこと (再起動していないこと) を確かめる。

```bash
for h in swfs-cluster-1 swfs-cluster-2 swfs-cluster-3; do
  echo "=== $h"
  ssh "$h" 'sudo systemctl start nixos-upgrade' || { echo "NG: $h で失敗"; ssh "$h" 'journalctl -u nixos-upgrade -n 30 --no-pager -o cat'; break; }
  ssh "$h" 'systemctl show -p ActiveEnterTimestamp --value keepalived'
done
```

続けて、3 台を同時に reload する。引数は、反映の前の認証ファイルのハッシュと、3 台のホスト名である。

このスクリプトは、前と後に次を確かめる。

- 前：認証ファイルが 3 台でそろって新しい値になっていること。そうでなければ止まる。
- 後：VIP の持ち主が変わらないこと。認証の失敗や状態の遷移が記録に無いこと。

```bash
bash -s -- <反映前のハッシュの先頭 12 文字> swfs-cluster-1 swfs-cluster-2 swfs-cluster-3 <<'EOF'
set -eu
old=$1; shift
vip() { for h in "$@"; do echo "$h $(ssh -n "$h" 'ip -br -4 addr' | grep -oE '(10\.20\.1\.(20|40|50|60)|192\.168\.5\.200)/' | tr '\n' ' ')"; done; }
all=""
for h in "$@"; do
  x=$(ssh -n "$h" 'sudo sha256sum /run/secrets/rendered/keepalived-auth.conf' | cut -c1-12)
  echo "$h: $x"
  [ "$x" != "$old" ] || { echo "$h はまだ古い値。reload せずに止める"; exit 1; }
  all="$all $x"
done
[ "$(echo $all | tr ' ' '\n' | sort -u | wc -l | tr -d ' ')" = 1 ] || { echo "3 台の値がそろっていない。reload せずに止める"; exit 1; }
before=$(vip "$@"); echo "--- reload 前"; echo "$before"
for h in "$@"; do ssh -n "$h" 'sudo systemctl reload keepalived' & done; wait
sleep 10
after=$(vip "$@"); echo "--- reload 後"; echo "$after"
[ "$before" = "$after" ] && echo "OK: VIP は動いていない" || echo "NG: VIP が動いた"
for h in "$@"; do echo "== $h"; ssh -n "$h" 'journalctl -u keepalived --since "-1min" --no-pager -o cat | grep -iE "passw|auth|Entering|MASTER|BACKUP|reload" || echo "(記録なし)"'; done
echo 終わり
EOF
```

ハッシュは、値を表示せずに「変わったか」「そろったか」を比べるためだけに使う。この記録やコメントには残さない。

## 結果

| クラスタ | VIP の持ち主 (前後で同じ) | reload の後の認証の失敗・状態の遷移 |
| :-- | :-- | :-- |
| swfs | swfs-cluster-1 (`10.20.1.60`) | 0 件 |
| pg | pg-cluster-1 (`10.20.1.40`)・pg-cluster-2 (`10.20.1.50`) | 0 件 |
| lb | lb-3 (`10.20.1.20`・`192.168.5.200`) | 0 件 |

- どのクラスタでも、reload の同じ秒の中で `received an invalid passwd` が数回出た。先に reload したホストの新しい値の合図を、まだ reload していないホストが受けたためで、3 秒には届かず遷移は起きなかった。
- 反映の間、keepalived も Patroni も再起動していない。Patroni は leader 1 台・quorum_standby 2 台のまま、lag 0 だった。
- lb の後に、`192.168.5.200` の DNS で `pechka.wpcapp.net` が引け、`https://pechka.wpcapp.net/` が 200 を返すことを確かめた。
- bluray-extractor は nixos-upgrade の後、取り込みのジョブに `MINIO_BUCKET="pechka"` が渡り、次の実行も成功した。

## つまずいたこと

- **`bash -s <<'EOF'` の中の `ssh` は、残りのスクリプトを読んでしまう。** 最初は `-n` を付けておらず、ループの中の最初の `ssh` が残りを入力として読み込んだ。スクリプトは途中で黙って終わり、reload はされなかった。heredoc で渡すスクリプトの中の `ssh` には `-n` を付ける。
- **zsh では、文字列の中の `!!` が直前のコマンドに化ける** (履歴の展開)。失敗時の表示に `!!!` を使っていたら、別のコマンドに置き換わった。表示には `NG:` を使う。
- **Mac の zsh は、打ち込んだコマンドの `#` をコメントとして扱わなかった** (`interactivecomments` が無効)。`&` を含むコメントがコマンドとして走った。今は有効にしてある。
