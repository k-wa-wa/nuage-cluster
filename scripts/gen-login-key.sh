#!/usr/bin/env bash
set -euo pipefail

# ログイン用の SSH 鍵 (ed25519) を作り、秘密鍵を SOPS のファイル (.ssh/login-keys.yaml) に入れる。
# 同じ秘密鍵を、この Mac でそのまま使えるよう .ssh/keys/<名前> にも置く (.gitignore 済み)。
# 鍵は接続元ごとに 1 本とする (例: nixos は Mac から各 NixOS ホストの nixos ユーザーに入る鍵)。
# 同じ名前を指定すると鍵を作り直す (ローテーション)。作り直したら、公開鍵を入る先に足してから古い鍵を外す。
#
# 使い方: cd nuage-cluster && bash scripts/gen-login-key.sh <名前>

OUT=.ssh/login-keys.yaml
KEY_DIR=.ssh/keys

if [ ! -f .sops.yaml ] || [ ! -f .ssh/ssh_config ]; then
  echo "Error: リポジトリルート (nuage-cluster) で実行する" >&2
  exit 1
fi
if [ $# -ne 1 ]; then
  echo "使い方: bash scripts/gen-login-key.sh <名前>" >&2
  exit 1
fi
name=$1
case "$name" in
  *[!a-z0-9-]* | "")
    echo "Error: 名前は英小文字・数字・ハイフンだけにする" >&2
    exit 1
    ;;
esac
for cmd in sops jq ssh-keygen; do
  if ! command -v "$cmd" > /dev/null; then
    echo "Error: $cmd が無い" >&2
    exit 1
  fi
done

umask 077
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ssh-keygen -q -t ed25519 -N "" -C "$name" -f "$TMP/$name"

# 既にあるファイルには sops set で 1 つだけ足す。全体を暗号化し直すと他の鍵の暗号文まで変わり、差分でどの鍵が変わったか読めなくなる。
# 値は JSON の文字列にしてファイルで渡す (コマンドの引数に秘密を載せない)。
jq -Rs . "$TMP/$name" > "$TMP/value.json"
if [ -f "$OUT" ]; then
  sops set --value-file "$OUT" "[\"$name\"]" "$TMP/value.json"
else
  jq -n --arg n "$name" --slurpfile v "$TMP/value.json" '{($n): $v[0]}' > "$TMP/plain.json"
  sops encrypt --filename-override "$OUT" --input-type json --output-type yaml "$TMP/plain.json" > "$TMP/enc.yaml"
  mv "$TMP/enc.yaml" "$OUT"
fi

mkdir -p "$KEY_DIR"
mv "$TMP/$name" "$KEY_DIR/$name"
mv "$TMP/$name.pub" "$KEY_DIR/$name.pub"

echo "秘密鍵を $OUT と $KEY_DIR/$name に書いた ($OUT を commit して push する)"
echo "公開鍵:"
cat "$KEY_DIR/$name.pub"
