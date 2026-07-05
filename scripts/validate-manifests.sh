#!/usr/bin/env bash

set -euo pipefail

# PATHの優先指定
export PATH=$HOME/.nix-profile/bin:$PATH

echo "=== Kubernetes Manifest Validation ==="

# 検証対象のディレクトリリスト
targets=(
  "manifests/bootstrap"
  "manifests/bootstrap/argocd"
  "manifests/common"
  "manifests/common/cilium"
)

# manifests/apps/*/overlays/prod を追加
for dir in manifests/apps/*/overlays/prod; do
  if [ -d "$dir" ]; then
    targets+=("$dir")
  fi
done

failed=0

for target in "${targets[@]}"; do
  echo "Validating: $target"
  if ! kustomize build "$target" --enable-helm | kubeconform -strict -ignore-missing-schemas -summary; then
    echo "❌ Validation failed for $target"
    failed=1
  else
    echo "✅ Validation succeeded for $target"
  fi
  echo "--------------------------------------"
done

if [ $failed -ne 0 ]; then
  echo "❌ Some validations failed."
  exit 1
fi

echo "🎉 All manifest validations passed!"
