#!/usr/bin/env bash
set -euo pipefail

# ホストごとの SSH ホスト鍵 (ed25519) を作り、秘密鍵を SOPS のファイルに、公開鍵を .ssh/known_hosts に書く。
# ホスト鍵は sshd の鍵であり、sops-nix の Age 鍵も兼ねる (.sops.yaml の受信者は ssh-to-age で公開鍵から作る)。
# 秘密鍵は Terraform (terraform/pve/hosts-secrets) が各ホストの /var/lib/nix-provisioning へ置く。
# 指定したホストの鍵は作り直す (ローテーション)。作り直したら .sops.yaml の受信者を更新して updatekeys をかけ、
# hosts-secrets を apply する。平文の鍵は一時ディレクトリにだけ置き、終わったら消す。
# .ssh/ssh_config は .ssh/known_hosts で接続先を確かめるので、ホストに新しい鍵が届くまでは入れない。その間は -o StrictHostKeyChecking=no を付ける。
#
# --sign-only を付けた場合は既存のホスト鍵を作り直さず、.ssh/known_hosts の公開鍵に対して
# SOPS 管理下の SSH CA (terraform/pve/hosts-secrets/ssh-ca.yaml) でホスト証明書 (.ssh/certs/<host>-cert.pub) を署名する。
# nix/hosts/<host>/ が存在するホストでは nix/hosts/<host>/<host>-cert.pub にも複製する (./nix がサブディレクトリ Flake であるため)。
#
# 使い方:
#   cd nuage-cluster && bash scripts/gen-host-keys.sh <ホスト名>...
#   cd nuage-cluster && bash scripts/gen-host-keys.sh --sign-only <ホスト名>...
# ホスト名は .ssh/ssh_config にあるものに限る (known_hosts に書く IP をそこから引く)。

OUT=terraform/pve/hosts-secrets/host-keys.yaml
SSH_CA=terraform/pve/hosts-secrets/ssh-ca.yaml
SSH_CA_PUB=.ssh/ssh-ca.pub
SPIRE_CA_PUB=manifests/apps/spire/base/ssh-ca.pub
KNOWN_HOSTS=.ssh/known_hosts
CERTS_DIR=.ssh/certs
CERT_VALIDITY="+520w"

usage() {
  local exit_code="${1:-1}"
  echo "使い方: bash scripts/gen-host-keys.sh [--sign-only] <ホスト名>..." >&2
  exit "$exit_code"
}

SIGN_ONLY=false
HOSTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --sign-only)
      SIGN_ONLY=true
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    -*)
      echo "Error: 不明なオプション: $1" >&2
      usage 1
      ;;
    *)
      HOSTS+=("$1")
      shift
      ;;
  esac
done

if [ ! -f .sops.yaml ] || [ ! -f .ssh/ssh_config ]; then
  echo "Error: リポジトリルート (nuage-cluster) で実行する" >&2
  exit 1
fi
if [ "${#HOSTS[@]}" -eq 0 ]; then
  usage 1
fi
for cmd in sops jq ssh-keygen awk; do
  if ! command -v "$cmd" > /dev/null; then
    echo "Error: $cmd が無い" >&2
    exit 1
  fi
done

umask 077
TMP=$(mktemp -d)
BACKUP_HOST_KEYS=""
cleanup() {
  if [ -n "$BACKUP_HOST_KEYS" ] && [ -f "$BACKUP_HOST_KEYS" ]; then
    cp "$BACKUP_HOST_KEYS" "$OUT"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

host_ip() {
  ssh -F .ssh/ssh_config -G "$1" | awk '$1 == "hostname" { print $2 }'
}

# 1 台ずつ書き換えるので、途中で止まって一部だけ変わらないよう、先に全ホストを確かめる。
for h in "${HOSTS[@]}"; do
  ip=$(host_ip "$h")
  if [ -z "$ip" ] || [ "$ip" = "$h" ]; then
    echo "Error: $h は .ssh/ssh_config に無い" >&2
    exit 1
  fi
  if [ "$SIGN_ONLY" = "true" ]; then
    pub=$(awk -v host="$h" '$1 ~ ("^" host ",") { print $2, $3; exit }' "$KNOWN_HOSTS" 2>/dev/null || true)
    if [ -z "$pub" ]; then
      echo "Error: $h の公開鍵が $KNOWN_HOSTS に無い" >&2
      exit 1
    fi
  fi
done

# 署名が必要な場合は、既存ファイルを変更する前に CA 秘密鍵の復号と両配布先公開鍵 (.ssh/ssh-ca.pub, manifests/apps/spire/base/ssh-ca.pub) の一致を検証する。
load_and_verify_ca() {
  if [ ! -f "$SSH_CA" ]; then
    echo "Error: SSH CA 秘密鍵 ($SSH_CA) が無い。先に生成して SOPS 暗号化すること" >&2
    exit 1
  fi
  if [ ! -s "$SSH_CA_PUB" ]; then
    echo "Error: SSH CA 公開鍵 ($SSH_CA_PUB) が無い、または空である" >&2
    exit 1
  fi
  if [ ! -s "$SPIRE_CA_PUB" ]; then
    echo "Error: SPIRE 用 SSH CA 公開鍵 ($SPIRE_CA_PUB) が無い、または空である" >&2
    exit 1
  fi

  sops -d --extract '["private_key"]' "$SSH_CA" > "$TMP/ssh-ca"
  chmod 600 "$TMP/ssh-ca"

  local ca_from_priv ca_from_ssh ca_from_spire
  ca_from_priv=$(ssh-keygen -y -f "$TMP/ssh-ca" | awk '{print $1, $2}')
  ca_from_ssh=$(awk '{print $1, $2; exit}' "$SSH_CA_PUB")
  ca_from_spire=$(awk '{print $1, $2; exit}' "$SPIRE_CA_PUB")

  if [ -z "$ca_from_priv" ] || [ "$ca_from_priv" != "$ca_from_ssh" ]; then
    echo "Error: $SSH_CA の公開鍵が $SSH_CA_PUB と一致しない" >&2
    exit 1
  fi
  if [ "$ca_from_priv" != "$ca_from_spire" ]; then
    echo "Error: $SSH_CA の公開鍵が $SPIRE_CA_PUB と一致しない" >&2
    exit 1
  fi
}

stage_signed_cert() {
  local host="$1"
  local pubkey_file="$2"

  # ssh-keygen -s は公開鍵ファイルの横に <name>-cert.pub を生成する。
  # -n "<host>" でホスト名を先頭 principal に置き、SPIRE sshpop の agent_path_template (.Hostname) と一致させる。
  ssh-keygen -q -s "$TMP/ssh-ca" -I "$host" -h -n "$host" -V "$CERT_VALIDITY" "$pubkey_file"
  local generated="${pubkey_file%.pub}-cert.pub"
  if [ ! -s "$generated" ]; then
    echo "Error: $host のホスト証明書生成に失敗した" >&2
    exit 1
  fi
  if [ "$generated" != "$TMP/${host}-cert.pub" ]; then
    mv "$generated" "$TMP/${host}-cert.pub"
  fi
}

commit_signed_cert() {
  local host="$1"
  mkdir -p "$CERTS_DIR"
  chmod 755 "$CERTS_DIR"
  install -m 0644 "$TMP/${host}-cert.pub" "$CERTS_DIR/${host}-cert.pub"
  if [ -d "nix/hosts/${host}" ]; then
    install -m 0644 "$TMP/${host}-cert.pub" "nix/hosts/${host}/${host}-cert.pub"
    echo "$host のホスト証明書を $CERTS_DIR/${host}-cert.pub と nix/hosts/${host}/${host}-cert.pub に書いた"
  else
    echo "$host のホスト証明書を $CERTS_DIR/${host}-cert.pub に書いた"
  fi
}

if [ "$SIGN_ONLY" = "true" ]; then
  load_and_verify_ca
  for h in "${HOSTS[@]}"; do
    awk -v host="$h" '$1 ~ ("^" host ",") { print $2, $3; exit }' "$KNOWN_HOSTS" > "$TMP/${h}.pub"
    stage_signed_cert "$h" "$TMP/${h}.pub"
  done
  for h in "${HOSTS[@]}"; do
    commit_signed_cert "$h"
  done
  echo "署名済みホスト証明書を commit して push する"
  exit 0
fi

# 既にホスト証明書が発行済みのホストが含まれる場合は、鍵更新前に CA を検証し再署名まで一時領域で完了させる。
resign_hosts=()
for h in "${HOSTS[@]}"; do
  if [ -f "$CERTS_DIR/${h}-cert.pub" ] || [ -f "nix/hosts/${h}/${h}-cert.pub" ]; then
    resign_hosts+=("$h")
  fi
done
if [ "${#resign_hosts[@]}" -gt 0 ]; then
  load_and_verify_ca
fi

echo '{}' > "$TMP/plain.json"
touch "$KNOWN_HOSTS"
cp "$KNOWN_HOSTS" "$TMP/known_hosts"

for h in "${HOSTS[@]}"; do
  ip=$(host_ip "$h")
  ssh-keygen -q -t ed25519 -N "" -C "root@$h" -f "$TMP/$h"
  jq -Rs . "$TMP/$h" > "$TMP/$h.json"
  grep -v "^$h," "$TMP/known_hosts" > "$TMP/kh" || true
  echo "$h,$ip $(cut -d' ' -f1,2 "$TMP/$h.pub")" >> "$TMP/kh"
  mv "$TMP/kh" "$TMP/known_hosts"
done

for h in "${resign_hosts[@]}"; do
  stage_signed_cert "$h" "$TMP/${h}.pub"
done

# ここまでで鍵生成・known_hosts 準備・再署名がすべて成功した。次に host-keys.yaml を更新する (失敗時は元へ戻す)。
if [ -f "$OUT" ]; then
  cp "$OUT" "$TMP/host-keys.orig.yaml"
  BACKUP_HOST_KEYS="$TMP/host-keys.orig.yaml"
  for h in "${HOSTS[@]}"; do
    # 既にあるファイルには sops set で 1 台ずつ足す。全体を暗号化し直すと他のホストの暗号文まで変わり、差分でどのホストが変わったか読めなくなる。
    # 値は JSON の文字列にしてファイルで渡す (コマンドの引数に秘密を載せない)。
    sops set --value-file "$OUT" "[\"$h\"]" "$TMP/$h.json"
  done
else
  for h in "${HOSTS[@]}"; do
    jq --arg h "$h" --slurpfile v "$TMP/$h.json" '.[$h] = $v[0]' "$TMP/plain.json" > "$TMP/next.json"
    mv "$TMP/next.json" "$TMP/plain.json"
  done
  sops encrypt --filename-override "$OUT" --input-type json --output-type yaml "$TMP/plain.json" > "$TMP/enc.yaml"
  mv "$TMP/enc.yaml" "$OUT"
fi
BACKUP_HOST_KEYS=""

sort "$TMP/known_hosts" > "$KNOWN_HOSTS"
for h in "${HOSTS[@]}"; do
  ip=$(host_ip "$h")
  echo "$h ($ip) の鍵を作った"
done
for h in "${resign_hosts[@]}"; do
  commit_signed_cert "$h"
done

echo "秘密鍵を $OUT に、公開鍵を $KNOWN_HOSTS に書いた (commit して push する)"
