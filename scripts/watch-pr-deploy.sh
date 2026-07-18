#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

if [ $# -lt 2 ]; then
    echo "Usage: $0 <APP_NAME> <PR_NUMBER>"
    exit 1
fi

APP_NAME=$1
PR_NUMBER=$2

ARGOCD_APP="${APP_NAME}-pr-${PR_NUMBER}"
NAMESPACE="${APP_NAME}-pr-${PR_NUMBER}"
REPO_DIR="../${APP_NAME}"

# 最新のコミットハッシュを対象リポジトリから取得
if [ -d "$REPO_DIR" ]; then
    TARGET_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
else
    echo "Error: Repository directory not found at $REPO_DIR"
    exit 1
fi

echo "Target Commit: ${TARGET_COMMIT}"
echo "Monitoring Argo CD Application '${ARGOCD_APP}'..."

# 1. Argo CD Applicationの targetRevision が最新コミットになるのを待つ
while true; do
    CURRENT_REVISION=$(kubectl get application "${ARGOCD_APP}" -n argocd -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null || true)
    if [ "${CURRENT_REVISION}" = "${TARGET_COMMIT}" ]; then
        echo "Argo CD detected the new commit: ${TARGET_COMMIT}"
        break
    fi
    echo "Waiting for Argo CD to detect new commit... (current: ${CURRENT_REVISION:-None})"
    sleep 10
done

# 2. Deployment の更新と起動を待つ
echo "Waiting for deployments in namespace '${NAMESPACE}' to roll out..."
for deploy in api frontend; do
    echo "Waiting for deployment/${deploy}..."
    kubectl rollout status deployment/${deploy} -n "${NAMESPACE}"
done

echo "🎉 All deployments are successfully updated and Ready!"
