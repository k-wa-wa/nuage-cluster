#!/bin/sh
set -u

FAILED=0

echo "=== Starting Preview Environment Security & Network Isolation Test ==="

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

check_readonly_path() {
  name="$1"
  path="$2"

  # 1. /proc/self/mountinfo から該当マウントポイントのオプションを取得し、ro が指定されているか検証
  if [ -r /proc/self/mountinfo ]; then
    mount_opts="$(awk -v target="$path" '$5 == target { opts = $6 } END { print opts }' /proc/self/mountinfo)"
    if [ -z "$mount_opts" ]; then
      echo "[FAIL] Mount point not found in /proc/self/mountinfo: ${name} (${path})"
      FAILED=1
      return
    fi
    if ! echo "$mount_opts" | grep -Eq "(^|,)ro(,|$)"; then
      echo "[FAIL] Mount point is not mounted read-only (opts: ${mount_opts}): ${name} (${path})"
      FAILED=1
      return
    fi
  fi

  # 2. 実際の書き込み試行が EROFS (Read-only file system) で拒否されるか検証
  probe="${path}/.__isolation_test_probe_$$"
  out="$(touch "$probe" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$probe" >/dev/null 2>&1 || true
    echo "[FAIL] Read-only path unexpectedly writable: ${name} (${path})"
    FAILED=1
  elif echo "$out" | grep -qi "Read-only"; then
    echo "[PASS] Read-only path verified (mount is ro and write rejected with EROFS): ${name} (${path})"
  else
    echo "[FAIL] Read-only path write did not fail with EROFS (Read-only file system): ${name} (${path}) - ${out}"
    FAILED=1
  fi
}

check_no_host_devices() {
  found_devs=""
  for dev_pattern in /dev/sd* /dev/vd* /dev/nvme* /dev/xvd* /dev/dm-*; do
    if [ -e "$dev_pattern" ]; then
      found_devs="${found_devs} ${dev_pattern}"
    fi
  done

  if [ -n "$found_devs" ]; then
    echo "[FAIL] Host raw block device(s) exposed in /dev:${found_devs}"
    FAILED=1
  else
    echo "[PASS] No raw host block devices exposed in /dev (/dev/sd*, /dev/vd*, /dev/nvme*, etc.)"
  fi
}

check_capabilities() {
  if [ ! -r /proc/self/status ]; then
    echo "[FAIL] Cannot read /proc/self/status for capability audit"
    FAILED=1
    return
  fi

  capeff_hex="$(awk '/^CapEff:/ {print $2}' /proc/self/status)"
  if [ -z "$capeff_hex" ]; then
    echo "[FAIL] CapEff not found in /proc/self/status"
    FAILED=1
    return
  fi

  capeff_val=$(( 0x${capeff_hex} ))

  # 危険な特権ケーパビリティビットの定義
  # CAP_SYS_ADMIN:  bit 21 (0x00200000)
  # CAP_SYS_MODULE: bit 16 (0x00010000)
  # CAP_SYS_RAWIO:  bit 17 (0x00020000)
  # CAP_SYS_PTRACE: bit 19 (0x00080000)
  # CAP_SYS_BOOT:   bit 22 (0x00400000)
  cap_admin=$(( 0x00200000 ))
  cap_module=$(( 0x00010000 ))
  cap_rawio=$(( 0x00020000 ))
  cap_ptrace=$(( 0x00080000 ))
  cap_boot=$(( 0x00400000 ))

  found_dangerous=""
  if [ $(( capeff_val & cap_admin )) -ne 0 ]; then
    found_dangerous="${found_dangerous} CAP_SYS_ADMIN(0x200000)"
  fi
  if [ $(( capeff_val & cap_module )) -ne 0 ]; then
    found_dangerous="${found_dangerous} CAP_SYS_MODULE(0x10000)"
  fi
  if [ $(( capeff_val & cap_rawio )) -ne 0 ]; then
    found_dangerous="${found_dangerous} CAP_SYS_RAWIO(0x20000)"
  fi
  if [ $(( capeff_val & cap_ptrace )) -ne 0 ]; then
    found_dangerous="${found_dangerous} CAP_SYS_PTRACE(0x80000)"
  fi
  if [ $(( capeff_val & cap_boot )) -ne 0 ]; then
    found_dangerous="${found_dangerous} CAP_SYS_BOOT(0x400000)"
  fi

  if [ -n "$found_dangerous" ]; then
    echo "[FAIL] Dangerous capability retained in CapEff (${capeff_hex}):${found_dangerous}"
    FAILED=1
  else
    echo "[PASS] No dangerous capabilities retained in CapEff (${capeff_hex})"
  fi
}

# --- 1. ネットワーク遮断テスト ---

# 1.1 遮断テスト: 自宅 LAN / Proxmox (PBS)
check_blocked "Home LAN / PBS" "192.168.5.30" "8007"

# 1.2 遮断テスト: k8s コントロールプレーン (Talos API)
check_blocked "k8s Control Plane / Talos API" "10.20.1.11" "50000"

# 1.3 遮断テスト: ノード Kubelet API
check_blocked "Node Kubelet API" "10.20.1.11" "10250"

# 1.4 遮断テスト: Cilium ヘルスチェックポート
check_blocked "Cilium Health Check" "10.20.1.11" "4240"

# 1.5 遮断テスト: クラウド／リンクローカルメタデータ
check_blocked "Cloud Metadata / Link-Local" "169.254.169.254" "80"

# 1.6 遮断テスト: k8s API サーバー (kubernetes.default)
check_blocked "k8s API Server (kubernetes.default)" "10.96.0.1" "443"

# 1.7 遮断テスト: 他 Namespace / システム Namespace (Argo CD Server)
check_blocked "Other Namespace / Argo CD Server" "argocd-server.argocd.svc.cluster.local" "80"

# --- 2. ネットワーク許可テスト ---

# 2.1 許可テスト: CoreDNS (TCP 53 および UDP 名前解決)
check_allowed "CoreDNS (TCP)" "10.96.0.10" "53"
check_dns_udp "CoreDNS (UDP nslookup)" "kubernetes.default.svc.cluster.local" "10.96.0.10"

# 2.2 許可テスト: パブリックインターネット (Cloudflare)
check_allowed "Public Internet (Cloudflare)" "1.1.1.1" "443"

# 2.3 許可テスト: pechka 本番外部リソース (MinIO / SeaweedFS S3 VIP および PostgreSQL VIP)
check_allowed "pechka Prod MinIO (SeaweedFS VIP)" "10.20.1.60" "9000"
check_allowed "pechka Prod PostgreSQL (VIP)" "10.20.1.40" "5432"

# --- 3. コンテナ・ランタイム境界の健全性検証 ---

# 3.1 Masked / Read-Only パスの検証
check_readonly_path "Kernel Sysctl (/proc/sys)" "/proc/sys"
check_readonly_path "Sysfs (/sys)" "/sys"

# 3.2 ホスト生ブロックデバイスの非露出検証
check_no_host_devices

# 3.3 Linux 特権ケーパビリティの非保持検証
check_capabilities

if [ "$FAILED" -ne 0 ]; then
  echo "=== Isolation Test FAILED ==="
  exit 1
fi

echo "=== All Isolation Tests PASSED ==="
exit 0
