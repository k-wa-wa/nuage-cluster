#!/usr/bin/env nix-shell
#!nix-shell -i bash -p kustomize kubeconform pluto conftest jq yamllint kubernetes-helm -I nixpkgs=channel:nixpkgs-unstable

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

TMP_DIR=""
cleanup() {
  if [ -n "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

LOCAL_RUNNER="${HOME}/ghq/github.com/k-wa-wa/nuage-workspace/.github/workflows/validate/k8s/run.sh"
if [ -x "$LOCAL_RUNNER" ]; then
  RUNNER="$LOCAL_RUNNER"
else
  TMP_DIR="$(mktemp -d)"
  curl -sSfL "https://github.com/k-wa-wa/nuage-workspace/archive/refs/heads/master.tar.gz" \
    | tar -xz -C "$TMP_DIR" "nuage-workspace-master/.github/workflows/validate/k8s"
  RUNNER="${TMP_DIR}/nuage-workspace-master/.github/workflows/validate/k8s/run.sh"
fi

FAILED=0

echo "=== 1. Validate Prod Apps (yamllint + prod HA policy) ==="
if ! "$RUNNER" \
  --enable-helm \
  --yamllint-path "manifests" \
  --prod \
  --fail-on-policy true \
  --targets "manifests/apps/*/overlays/prod"; then
  FAILED=1
fi
echo ""

echo "=== 2. Validate Apps Root Manifests (common policy) ==="
if ! "$RUNNER" \
  --enable-helm \
  --fail-on-policy true \
  --targets "manifests/apps/*.yaml"; then
  FAILED=1
fi
echo ""

echo "=== 3. Validate Bootstrap (schema/pluto required, policy warning only) ==="
if ! "$RUNNER" \
  --enable-helm \
  --fail-on-policy false \
  --targets "manifests/bootstrap/kustomization.yaml"; then
  FAILED=1
fi
echo ""

if [ "$FAILED" -ne 0 ]; then
  echo "❌ Kubernetes manifest validation failed!"
  exit 1
fi

echo "✅ All Kubernetes manifest validations passed!"
