#!/usr/bin/env bash
set -euo pipefail

# ホストごとの SSH ホスト鍵 (ed25519) を作り、秘密鍵を SOPS のファイルに、公開鍵を .ssh/known_hosts に書く。
# ホスト鍵は sshd の鍵であり、sops-nix の Age 鍵も兼ねる (.sops.yaml の受信者は ssh-to-age で公開鍵から作る)。
# 秘密鍵は Terraform (terraform/pve/hosts-secrets) が各ホストの /var/lib/nix-provisioning へ置く。
# 指定したホストの鍵は作り直す (ローテーション)。作り直したら .sops.yaml の受信者を更新して updatekeys をかけ、
# hosts-secrets を apply する。平文の鍵は一時ディレクトリにだけ置き、終わったら消す。
#
# 使い方: cd nuage-cluster && bash scripts/gen-host-keys.sh <ホスト名>...
# ホスト名は .ssh/ssh_config にあるものに限る (known_hosts に書く IP をそこから引く)。

OUT=terraform/pve/hosts-secrets/host-keys.yaml
KNOWN_HOSTS=.ssh/known_hosts

if [ ! -f .sops.yaml ] || [ ! -f .ssh/ssh_config ]; then
  echo "Error: リポジトリルート (nuage-cluster) で実行する" >&2
  exit 1
fi
if [ $# -eq 0 ]; then
  echo "使い方: bash scripts/gen-host-keys.sh <ホスト名>..." >&2
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

if [ -f "$OUT" ]; then
  sops decrypt --output-type json "$OUT" > "$TMP/plain.json"
else
  echo '{}' > "$TMP/plain.json"
fi
touch "$KNOWN_HOSTS"
cp "$KNOWN_HOSTS" "$TMP/known_hosts"

for h in "$@"; do
  ip=$(ssh -F .ssh/ssh_config -G "$h" | awk '$1 == "hostname" { print $2 }')
  if [ -z "$ip" ] || [ "$ip" = "$h" ]; then
    echo "Error: $h は .ssh/ssh_config に無い" >&2
    exit 1
  fi

  ssh-keygen -q -t ed25519 -N "" -C "root@$h" -f "$TMP/$h"
  jq --arg h "$h" --rawfile k "$TMP/$h" '.[$h] = $k' "$TMP/plain.json" > "$TMP/next.json"
  mv "$TMP/next.json" "$TMP/plain.json"

  grep -v "^$h," "$TMP/known_hosts" > "$TMP/kh" || true
  echo "$h,$ip $(cut -d' ' -f1,2 "$TMP/$h.pub")" >> "$TMP/kh"
  mv "$TMP/kh" "$TMP/known_hosts"
  echo "$h ($ip) の鍵を作った"
done

sops encrypt --filename-override "$OUT" --input-type json --output-type yaml "$TMP/plain.json" > "$TMP/enc.yaml"
mv "$TMP/enc.yaml" "$OUT"
sort "$TMP/known_hosts" > "$KNOWN_HOSTS"
echo "秘密鍵を $OUT に、公開鍵を $KNOWN_HOSTS に書いた (commit して push する)"
