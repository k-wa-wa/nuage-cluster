#!/usr/bin/env bash
# scripts/gen-host-keys.sh の署名・ローテーション・CA 照合ロジックの回帰テスト。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/gen-host-keys.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

setup_mock_repo() {
  local dir="$TMP/$1"
  mkdir -p "$dir/.ssh/certs" "$dir/manifests/apps/spire/base" "$dir/terraform/pve/hosts-secrets" "$dir/nix/hosts/atelier" "$dir/scripts" "$dir/bin"
  cp "$SCRIPT" "$dir/scripts/gen-host-keys.sh"
  chmod +x "$dir/scripts/gen-host-keys.sh"
  cp "$REPO_ROOT/.sops.yaml" "$dir/.sops.yaml"
  cat > "$dir/.ssh/ssh_config" <<'EOF'
Host atelier
    HostName 192.168.5.252
EOF

  # テスト用ホスト鍵ペアと known_hosts
  ssh-keygen -q -t ed25519 -N "" -C "root@atelier" -f "$dir/host_init"
  echo "atelier,192.168.5.252 $(cut -d' ' -f1,2 "$dir/host_init.pub")" > "$dir/.ssh/known_hosts"
  echo "ORIG_HOST_KEYS" > "$dir/terraform/pve/hosts-secrets/host-keys.yaml"

  # テスト用 CA 鍵ペア (正当 CA と別 CA)
  ssh-keygen -q -t ed25519 -N "" -C "ca-1" -f "$dir/ca1"
  ssh-keygen -q -t ed25519 -N "" -C "ca-2" -f "$dir/ca2"

  # モック sops (ssh-ca.yaml の読み取りと host-keys.yaml の書き込みを再現)
  cat > "$dir/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-d" ]; then
  # 4 番目の引数がファイル
  cat "${@: -1}"
elif [ "$1" = "set" ]; then
  file="$3"
  val_file="$5"
  printf 'UPDATED_WITH:%s\n' "$(head -c 20 "$val_file")" > "$file"
elif [ "$1" = "encrypt" ]; then
  cat
else
  exit 1
fi
EOF
  chmod +x "$dir/bin/sops"
  echo "$dir"
}

echo "=== Test 1: --help exits with 0 ==="
d1=$(setup_mock_repo t1)
(cd "$d1" && bash scripts/gen-host-keys.sh --help >/dev/null 2>&1)

echo "=== Test 2: --sign-only fails when CA file or pubkeys are missing/empty ==="
d2=$(setup_mock_repo t2)
if (cd "$d2" && PATH="$d2/bin:$PATH" bash scripts/gen-host-keys.sh --sign-only atelier >/dev/null 2>&1); then
  echo "FAIL: missing CA should fail" >&2
  exit 1
fi
cp "$d2/ca1" "$d2/terraform/pve/hosts-secrets/ssh-ca.yaml"
cp "$d2/ca1.pub" "$d2/.ssh/ssh-ca.pub"
: > "$d2/manifests/apps/spire/base/ssh-ca.pub"
if (cd "$d2" && PATH="$d2/bin:$PATH" bash scripts/gen-host-keys.sh --sign-only atelier >/dev/null 2>&1); then
  echo "FAIL: empty manifests ssh-ca.pub should fail" >&2
  exit 1
fi

echo "=== Test 3: --sign-only fails when manifests/apps/spire/base/ssh-ca.pub mismatches CA ==="
cp "$d2/ca2.pub" "$d2/manifests/apps/spire/base/ssh-ca.pub"
if (cd "$d2" && PATH="$d2/bin:$PATH" bash scripts/gen-host-keys.sh --sign-only atelier >/dev/null 2>&1); then
  echo "FAIL: mismatched spire pubkey should fail" >&2
  exit 1
fi
[ ! -e "$d2/.ssh/certs/atelier-cert.pub" ] || { echo "FAIL: cert should not be created on mismatch" >&2; exit 1; }

echo "=== Test 4: --sign-only succeeds and writes both cert paths ==="
cp "$d2/ca1.pub" "$d2/manifests/apps/spire/base/ssh-ca.pub"
(cd "$d2" && PATH="$d2/bin:$PATH" bash scripts/gen-host-keys.sh --sign-only atelier >/dev/null)
cmp -s "$d2/.ssh/certs/atelier-cert.pub" "$d2/nix/hosts/atelier/atelier-cert.pub"
ssh-keygen -L -f "$d2/.ssh/certs/atelier-cert.pub" | grep -q "atelier"

echo "=== Test 5: Rotation with existing cert aborts without mutating files when CA mismatches ==="
orig_kh=$(cat "$d2/.ssh/known_hosts")
orig_cert=$(cat "$d2/.ssh/certs/atelier-cert.pub")
cp "$d2/ca2.pub" "$d2/manifests/apps/spire/base/ssh-ca.pub"
if (cd "$d2" && PATH="$d2/bin:$PATH" bash scripts/gen-host-keys.sh atelier >/dev/null 2>&1); then
  echo "FAIL: rotation with mismatched CA should fail" >&2
  exit 1
fi
[ "$(cat "$d2/terraform/pve/hosts-secrets/host-keys.yaml")" = "ORIG_HOST_KEYS" ]
[ "$(cat "$d2/.ssh/known_hosts")" = "$orig_kh" ]
[ "$(cat "$d2/.ssh/certs/atelier-cert.pub")" = "$orig_cert" ]

echo "=== Test 6: Rotation with matching CA updates host-keys, known_hosts, and re-signs matching cert ==="
cp "$d2/ca1.pub" "$d2/manifests/apps/spire/base/ssh-ca.pub"
(cd "$d2" && PATH="$d2/bin:$PATH" bash scripts/gen-host-keys.sh atelier >/dev/null)
[ "$(cat "$d2/terraform/pve/hosts-secrets/host-keys.yaml")" != "ORIG_HOST_KEYS" ]
[ "$(cat "$d2/.ssh/known_hosts")" != "$orig_kh" ]
[ "$(cat "$d2/.ssh/certs/atelier-cert.pub")" != "$orig_cert" ]
cmp -s "$d2/.ssh/certs/atelier-cert.pub" "$d2/nix/hosts/atelier/atelier-cert.pub"
new_pub_fp=$(awk '{print $2, $3}' "$d2/.ssh/known_hosts" | ssh-keygen -lf - | awk '{print $2}')
cert_fp=$(ssh-keygen -Lf "$d2/.ssh/certs/atelier-cert.pub" | awk '/Public key:/ {print $4}')
[ "$new_pub_fp" = "$cert_fp" ]

echo "All gen-host-keys.sh tests passed!"
