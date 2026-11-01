#!/usr/bin/env bash
set -euo pipefail

# atelier のエージェントが各 NixOS ホストへ agent ユーザー (nix/modules/agent-user.nix) として
# SSH で入るための鍵 (ed25519) を作る。秘密鍵は SOPS のファイル (nix/hosts/atelier/secrets.yaml の agent_ed25519) に、
# 公開鍵は nix/modules/atelier-agent.pub に書く。
# atelier は sops-nix で秘密鍵を /run/secrets/agent_ed25519 に置き、/etc/ssh/ssh_config (nix/hosts/atelier/configuration.nix) で使う。
# 実行するたびに鍵を作り直す (ローテーション)。平文の鍵は一時ディレクトリにだけ置き、終わったら消す。
#
# 使い方: cd nuage-cluster && bash scripts/gen-atelier-agent-key.sh

OUT=nix/hosts/atelier/secrets.yaml
PUB_FILE=nix/modules/atelier-agent.pub
NAME=agent_ed25519

if [ ! -f .sops.yaml ] || [ ! -d nix/hosts/atelier ]; then
  echo "Error: リポジトリルート (nuage-cluster) で実行する" >&2
  exit 1
fi
for cmd in sops jq ssh-keygen; do
  if ! command -v "$cmd" > /dev/null; then
    echo "Error: $cmd が無い" >&2
    exit 1
  fi
done

umask 077
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

ssh-keygen -q -t ed25519 -N "" -C atelier-agent -f "$TMP/key"

# 既にあるファイルには sops set で 1 つだけ書き換える。全体を暗号化し直すと他の値の暗号文まで変わり、差分でどの値が変わったか読めなくなる。
# 値は JSON の文字列にしてファイルで渡す (コマンドの引数に秘密を載せない)。
jq -Rs . "$TMP/key" > "$TMP/value.json"
if [ -f "$OUT" ]; then
  sops set --value-file "$OUT" "[\"$NAME\"]" "$TMP/value.json"
else
  jq -n --arg n "$NAME" --slurpfile v "$TMP/value.json" '{($n): $v[0]}' > "$TMP/plain.json"
  sops encrypt --filename-override "$OUT" --input-type json --output-type yaml "$TMP/plain.json" > "$TMP/enc.yaml"
  mv "$TMP/enc.yaml" "$OUT"
fi

cut -d' ' -f1,2 "$TMP/key.pub" | sed 's/$/ atelier-agent/' > "$PUB_FILE"

echo "秘密鍵を $OUT に、公開鍵を $PUB_FILE に書いた (2 つとも commit して push する)"
cat "$PUB_FILE"
