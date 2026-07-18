#!/bin/bash

# スクリプトの絶対パスを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================
# 設定: "ホスト名:IPアドレス:ユーザー名" の形式で記述
# ==========================================
NODES=(
    "dev-server:192.168.5.199:nixos"
)

# 共通設定（SCRIPT_DIRをベースにする）
KEY_DIR="$SCRIPT_DIR/keys"

# ディレクトリ準備
mkdir -p "$KEY_DIR"

for entry in "${NODES[@]}"; do
    # ホスト名、IP、ユーザーを分割
    host="${entry%%:*}"

    PRIVATE_KEY="$KEY_DIR/$host"

    # 1. 鍵の生成
    if [ ! -f "$PRIVATE_KEY" ]; then
        ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -q
        echo "✅ SSH key generated for $host at $PRIVATE_KEY"
    else
        echo "ℹ️ SSH key for $host already exists at $PRIVATE_KEY"
    fi
done
