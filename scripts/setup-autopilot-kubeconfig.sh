#!/usr/bin/env bash
set -euo pipefail

# manifests/apps/autopilot/ がArgo CD経由でデプロイ済みであることを前提に、
# autopilot ServiceAccountのトークンからread-only専用のkubeconfigを組み立て、
# autopilot-server のデフォルトkubeconfigパス（~/.kube/config）に配置する。
# デフォルトパスに置くため、autopilot-server側でKUBECONFIG環境変数の設定は不要。
# secrets.env と同じくSOPSには載せず、生成物をこのスクリプトでautopilot-serverへ
# 手動配置する運用とする（nuage-workspace issue #8）。
#
# 使い方: cd nuage-cluster && bash scripts/setup-autopilot-kubeconfig.sh

export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig

NAMESPACE=autopilot
SECRET_NAME=autopilot-token
SA_NAME=autopilot
REMOTE_PATH='~/.kube/config'

CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

echo "Waiting for Secret/${SECRET_NAME} token to be populated..."
TOKEN=""
for _ in $(seq 1 30); do
  TOKEN=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
  if [ -n "${TOKEN}" ]; then
    break
  fi
  sleep 2
done
if [ -z "${TOKEN}" ]; then
  echo "Error: token not populated in Secret/${SECRET_NAME} (namespace ${NAMESPACE})" >&2
  exit 1
fi

CA_CRT_FILE=$(mktemp)
OUT_KUBECONFIG=$(mktemp)
trap 'rm -f "${CA_CRT_FILE}" "${OUT_KUBECONFIG}"' EXIT

kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.ca\.crt}' | base64 -d > "${CA_CRT_FILE}"

KUBECONFIG="${OUT_KUBECONFIG}" kubectl config set-cluster "${CLUSTER_NAME}" \
  --server="${SERVER}" \
  --certificate-authority="${CA_CRT_FILE}" \
  --embed-certs=true > /dev/null
KUBECONFIG="${OUT_KUBECONFIG}" kubectl config set-credentials "${SA_NAME}" \
  --token="${TOKEN}" > /dev/null
KUBECONFIG="${OUT_KUBECONFIG}" kubectl config set-context "${SA_NAME}" \
  --cluster="${CLUSTER_NAME}" \
  --user="${SA_NAME}" \
  --namespace="${NAMESPACE}" > /dev/null
KUBECONFIG="${OUT_KUBECONFIG}" kubectl config use-context "${SA_NAME}" > /dev/null

ssh -F .ssh/ssh_config autopilot-server "mkdir -p ~/.kube && install -m 600 /dev/null ${REMOTE_PATH}"
scp -F .ssh/ssh_config "${OUT_KUBECONFIG}" "autopilot-server:${REMOTE_PATH}"

echo "kubeconfig を autopilot-server:${REMOTE_PATH} に配置した"
