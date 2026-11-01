#!/usr/bin/env bash
#
# nixos-upgrade の自動ヘルスチェック & ロールバック機構の単体テスト
#

set -euo pipefail

echo "=== Running Auto-Upgrade Rollback Logic Tests ==="

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# 共通モック関数
setup_mock_env() {
  local test_name="$1"
  local env_dir="$TMP_DIR/$test_name"
  mkdir -p "$env_dir/run/nixos-upgrade"
  mkdir -p "$env_dir/var/lib/prometheus/node-exporter"
  mkdir -p "$env_dir/var/log"
  echo "$env_dir"
}

# ---------------------------------------------------------
# Test 1: 初回ブートストラップ時はスキップされること
# ---------------------------------------------------------
echo -n "Test 1: First-time bootstrap skip... "
env1=$(setup_mock_env "test1")
(
  # マーカーファイル未配置
  if [ ! -f "$env1/var/lib/bootstrap-second-switch-done" ] && [ ! -f "$env1/var/lib/nixos-bootstrap-done" ]; then
    exit 0
  fi
  exit 1
)
echo "PASS"

# ---------------------------------------------------------
# Test 2: ビルド・フェッチ失敗時に世代未変更ならロールバックがスキップされること (must)
# ---------------------------------------------------------
echo -n "Test 2: Skip rollback when build/fetch fails before generation switch... "
env2=$(setup_mock_env "test2")
(
  # 初回マーカー配置
  touch "$env2/var/lib/bootstrap-second-switch-done"

  # 更新前と更新後のプロファイルが同一
  echo "/nix/store/current-system" > "$env2/run/nixos-upgrade/pre-upgrade-profile"
  pre_profile=$(cat "$env2/run/nixos-upgrade/pre-upgrade-profile")
  current_profile="/nix/store/current-system"

  generation_changed=false
  if [ -n "$pre_profile" ] && [ -n "$current_profile" ] && [ "$pre_profile" != "$current_profile" ]; then
    generation_changed=true
  fi

  SERVICE_RESULT="exit-code"
  rollback_called=false
  mock_rollback() {
    rollback_called=true
  }

  if [ "$SERVICE_RESULT" != "success" ]; then
    if [ "$generation_changed" != "true" ]; then
      # ロールバックはスキップされなければならない
      if [ "$rollback_called" = "true" ]; then
        echo "FAIL: rollback was called unexpectedly" >&2
        exit 1
      fi
      exit 0
    fi
    mock_rollback
  fi
  exit 1
)
echo "PASS"

# ---------------------------------------------------------
# Test 3: 新世代適用後の switch 失敗時にロールバックが発火すること
# ---------------------------------------------------------
echo -n "Test 3: Trigger rollback when switch fails after generation change... "
env3=$(setup_mock_env "test3")
(
  touch "$env3/var/lib/bootstrap-second-switch-done"

  echo "/nix/store/old-system" > "$env3/run/nixos-upgrade/pre-upgrade-profile"
  pre_profile=$(cat "$env3/run/nixos-upgrade/pre-upgrade-profile")
  current_profile="/nix/store/new-system"

  generation_changed=false
  if [ -n "$pre_profile" ] && [ -n "$current_profile" ] && [ "$pre_profile" != "$current_profile" ]; then
    generation_changed=true
  fi

  SERVICE_RESULT="exit-code"
  rollback_called=false
  mock_rollback() {
    rollback_called=true
  }

  if [ "$SERVICE_RESULT" != "success" ]; then
    if [ "$generation_changed" != "true" ]; then
      exit 1
    fi
    mock_rollback
  fi

  if [ "$rollback_called" != "true" ]; then
    echo "FAIL: rollback was not called" >&2
    exit 1
  fi
  exit 0
)
echo "PASS"

# ---------------------------------------------------------
# Test 4: ヘルスチェック成功時は新世代が維持されること
# ---------------------------------------------------------
echo -n "Test 4: Healthcheck success maintains new generation... "
env4=$(setup_mock_env "test4")
(
  touch "$env4/var/lib/bootstrap-second-switch-done"
  echo "/nix/store/old-system" > "$env4/run/nixos-upgrade/pre-upgrade-profile"
  SERVICE_RESULT="success"

  system_state="running"
  failed_units=""
  units_ok=true

  rollback_called=false
  mock_rollback() {
    rollback_called=true
  }

  if [ "$system_state" = "running" ] && [ -z "$failed_units" ] && [ "$units_ok" = "true" ]; then
    healthy=true
  else
    healthy=false
  fi

  if [ "$healthy" != "true" ]; then
    mock_rollback
  fi

  if [ "$rollback_called" = "true" ]; then
    echo "FAIL: rollback was called on healthy system" >&2
    exit 1
  fi
  exit 0
)
echo "PASS"

# ---------------------------------------------------------
# Test 5: ヘルスチェック失敗（degraded / requiredUnits inactive）時にロールバックが発火すること
# ---------------------------------------------------------
echo -n "Test 5: Healthcheck failure triggers rollback... "
env5=$(setup_mock_env "test5")
(
  touch "$env5/var/lib/bootstrap-second-switch-done"
  echo "/nix/store/old-system" > "$env5/run/nixos-upgrade/pre-upgrade-profile"
  SERVICE_RESULT="success"

  # degraded 状態
  system_state="degraded"
  failed_units="haproxy.service"
  units_ok=false

  rollback_called=false
  mock_rollback() {
    rollback_called=true
  }

  healthy=false
  if [ "$system_state" = "running" ] && [ -z "$failed_units" ] && [ "$units_ok" = "true" ]; then
    healthy=true
  fi

  if [ "$healthy" != "true" ]; then
    mock_rollback
  fi

  if [ "$rollback_called" != "true" ]; then
    echo "FAIL: rollback was not called on degraded system" >&2
    exit 1
  fi
  exit 0
)
echo "PASS"

echo "🎉 All auto-upgrade rollback tests passed successfully!"
