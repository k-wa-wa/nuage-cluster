#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# プロジェクトルートから実行することを想定しています。
# lb-1 の HAProxy が 192.168.5.200:50000/6443 で各 API を
# TCP パススルーでプロキシしている前提です。
# ============================================================

export PATH="$PATH:$HOME/.nix-profile/bin"

SSH_KEY="./.ssh/id_ed25519_nixos"
LB_EXTERNAL_IP="192.168.5.200"   # lb-1 の HAProxy IP
TALOSCONFIG="terraform/vpc/zone-private-k8s/talosconfig"
CP01_IP="10.20.1.11"
KUBECONFIG_OUT="./kubeconfig"
MAX_RETRIES=60    # 最大 60 回 × 10 秒 = 10 分
RETRY_INTERVAL=10

# talosctl のフルパスを解決
TALOSCTL=$(command -v talosctl || echo "$HOME/.nix-profile/bin/talosctl")
echo "Using talosctl: ${TALOSCTL}"

TALOSCTL_ARGS="--talosconfig ${TALOSCONFIG} -e ${LB_EXTERNAL_IP}:50000 -n ${CP01_IP}"

# 1. Terragrunt Apply の実行
echo "=== Step 1: Running Terragrunt Apply ==="
terragrunt \
  --terragrunt-working-dir terraform/vpc/zone-private-k8s \
  apply -auto-approve

# 2. controlplane-01 が起動するまでポーリング
echo "=== Step 2: Waiting for controlplane-01 to become available ==="
for i in $(seq 1 $MAX_RETRIES); do
  echo "  [${i}/${MAX_RETRIES}] Checking Talos API at ${LB_EXTERNAL_IP}:50000 ..."
  SVCOUT=$("$TALOSCTL" $TALOSCTL_ARGS services 2>&1 || true)
  if echo "$SVCOUT" | grep -q "Running"; then
    echo "  => controlplane-01 is up!"
    break
  fi
  # エラーが出ていれば表示
  if echo "$SVCOUT" | grep -qi "error\|failed\|refused\|timeout"; then
    echo "    (reason: $(echo "$SVCOUT" | grep -i 'error\|failed\|refused\|timeout' | head -1))"
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "ERROR: controlplane-01 did not become available within $((MAX_RETRIES * RETRY_INTERVAL))s."
    exit 1
  fi
  sleep $RETRY_INTERVAL
done

# 3. Bootstrap (既に bootstrap 済みならスキップ)
echo "=== Step 3: Bootstrapping Talos Cluster ==="
set +e
BOOTSTRAP_ERR=$("$TALOSCTL" $TALOSCTL_ARGS bootstrap 2>&1)
BOOTSTRAP_RC=$?
set -e

if [ $BOOTSTRAP_RC -eq 0 ]; then
  echo "  => Bootstrap command sent successfully!"
elif echo "$BOOTSTRAP_ERR" | grep -qi "AlreadyExists\|already bootstrapped"; then
  echo "  => Cluster is already bootstrapped. Skipping."
else
  echo "ERROR: Bootstrap failed:"
  echo "$BOOTSTRAP_ERR"
  exit 1
fi

# 4. etcd が Running になるまで待機
echo "=== Step 4: Waiting for etcd to be Running ==="
for i in $(seq 1 $MAX_RETRIES); do
  echo "  [${i}/${MAX_RETRIES}] Checking etcd status ..."
  SVCOUT=$("$TALOSCTL" $TALOSCTL_ARGS services 2>&1 || true)
  if echo "$SVCOUT" | grep -q "etcd.*Running"; then
    echo "  => etcd is Running!"
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "ERROR: etcd did not start within $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
    exit 1
  fi
  sleep $RETRY_INTERVAL
done

# 5. kubeconfig を取得して書き出す
echo "=== Step 5: Downloading kubeconfig ==="
# shellcheck disable=SC2086
"$TALOSCTL" $TALOSCTL_ARGS kubeconfig "$KUBECONFIG_OUT" --force

# kubeconfig の server を lb-1 HAProxy (6443) に書き換える
sed -i.bak "s|server: https://.*:6443|server: https://${LB_EXTERNAL_IP}:6443|" "$KUBECONFIG_OUT"
rm -f "${KUBECONFIG_OUT}.bak"

echo ""
echo "=== All done! ==="
echo ""
echo "    KUBECONFIG=${KUBECONFIG_OUT} kubectl get nodes"
