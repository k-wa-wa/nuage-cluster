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
  
  # マニフェストのビルド結果を一時ファイルに格納
  tmp_manifest=$(mktemp)
  if ! kustomize build "$target" --enable-helm > "$tmp_manifest"; then
    echo "❌ Failed to build manifests for $target"
    failed=1
    rm -f "$tmp_manifest"
    echo "--------------------------------------"
    continue
  fi

  # 1. kubeconform によるスキーマ検証
  echo "--> Running kubeconform..."
  if ! kubeconform -strict -ignore-missing-schemas -summary < "$tmp_manifest"; then
    echo "❌ Schema validation failed for $target"
    failed=1
  fi

  # 2. kube-linter によるベストプラクティス検証
  echo "--> Running kube-linter..."
  if ! kube-linter lint - < "$tmp_manifest"; then
    echo "❌ Linter validation failed for $target"
    failed=1
  fi

  rm -f "$tmp_manifest"
  echo "--------------------------------------"
done

if [ $failed -ne 0 ]; then
  echo "❌ Some validations failed."
  exit 1
fi

echo "🎉 All manifest validations passed!"
