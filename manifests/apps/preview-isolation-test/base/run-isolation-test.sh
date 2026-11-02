#!/bin/sh
set -u

FAILED=0

echo "=== Starting Preview Environment Network Isolation Test ==="

# Cilium による パケット drop は必ずタイムアウト (Connection timed out) になる。
# busybox nc では -vv 指定時のみ Connection refused / Connection timed out 等が出力されるため、
# rc != 0 かつ出力に "Connection timed out" が含まれる場合のみ PASS とし、
# それ以外 (rc=0 の接続成功、Connection refused、No route to host、名前解決失敗等) はすべて FAIL とする。
check_blocked() {
  name="$1"
  host="$2"
  port="$3"
  out="$(nc -z -vv -w 3 "$host" "$port" 2>&1)"
  rc=$?
  if [ "$rc" -ne 0 ] && echo "$out" | grep -qi "Connection timed out"; then
    echo "[PASS] Blocked target dropped (timed out) as expected: ${name} (${host}:${port})"
  elif [ "$rc" -eq 0 ]; then
    echo "[FAIL] Blocked target reachable: ${name} (${host}:${port})"
    FAILED=1
  else
    echo "[FAIL] Blocked target did not time out (not dropped by policy): ${name} (${host}:${port}) - ${out}"
    FAILED=1
  fi
}

check_allowed() {
  name="$1"
  host="$2"
  port="$3"
  if nc -z -w 3 "$host" "$port" >/dev/null 2>&1; then
    echo "[PASS] Allowed target reachable as expected: ${name} (${host}:${port})"
  else
    echo "[FAIL] Allowed target unreachable: ${name} (${host}:${port})"
    FAILED=1
  fi
}

check_dns_udp() {
  name="$1"
  target_domain="$2"
  dns_server="$3"
  if nslookup "$target_domain" "$dns_server" >/dev/null 2>&1; then
    echo "[PASS] Allowed DNS UDP resolution succeeded as expected: ${name} (${target_domain} via ${dns_server})"
  else
    echo "[FAIL] Allowed DNS UDP resolution failed: ${name} (${target_domain} via ${dns_server})"
    FAILED=1
  fi
}

# 1. 遮断テスト: 自宅 LAN / Proxmox (PBS)
check_blocked "Home LAN / PBS" "192.168.5.30" "8007"

# 2. 遮断テスト: k8s コントロールプレーン (Talos API)
check_blocked "k8s Control Plane / Talos API" "10.20.1.11" "50000"

# 3. 遮断テスト: k8s API サーバー (kubernetes.default)
check_blocked "k8s API Server (kubernetes.default)" "10.96.0.1" "443"

# 4. 遮断テスト: 他 Namespace / システム Namespace (Argo CD Server)
check_blocked "Other Namespace / Argo CD Server" "argocd-server.argocd.svc.cluster.local" "80"

# 5. 許可テスト: CoreDNS (TCP 53 および UDP 名前解決)
check_allowed "CoreDNS (TCP)" "10.96.0.10" "53"
check_dns_udp "CoreDNS (UDP nslookup)" "kubernetes.default.svc.cluster.local" "10.96.0.10"

# 6. 許可テスト: パブリックインターネット (Cloudflare)
check_allowed "Public Internet (Cloudflare)" "1.1.1.1" "443"

# 7. 許可テスト: pechka 本番外部リソース (MinIO / SeaweedFS S3 VIP および PostgreSQL VIP)
check_allowed "pechka Prod MinIO (SeaweedFS VIP)" "10.20.1.60" "9000"
check_allowed "pechka Prod PostgreSQL (VIP)" "10.20.1.40" "5432"

if [ "$FAILED" -ne 0 ]; then
  echo "=== Isolation Test FAILED ==="
  exit 1
fi

echo "=== All Isolation Tests PASSED ==="
exit 0
