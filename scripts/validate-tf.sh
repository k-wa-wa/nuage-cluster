#!/usr/bin/env bash

set -euo pipefail

# PATHの優先指定（Nixのパスも含める）
export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

echo "=== Terraform Validation ==="

# 1. Terragrunt HCL Format Check
echo "Checking Terragrunt HCL format..."
terragrunt hclfmt --check

# 2. TFlint Check
echo "Running TFlint..."
# *.tf ファイルが存在するディレクトリを検索して tflint を実行
# .terragrunt-cache などの一時ディレクトリは除外する
find terraform -name "*.tf" -not -path "*/.terragrunt-cache/*" | while read -r file; do
  dir=$(dirname "$file")
  echo "Linting $dir with tflint..."
  # 警告（終了コード2）は許容し、重大なエラー（終了コード1）のみ失敗とする
  (cd "$dir" && (tflint || [ $? -eq 2 ]))
done

# 3. Terragrunt / OpenTofu Validation with Dummy Secrets
echo "Setting up dummy secrets for OpenTofu validation..."
TEMP_DIR=$(mktemp -d)

# 一時的な AGE 鍵ペアの生成
age-keygen -o "$TEMP_DIR/key.txt"
PUBKEY=$(grep "public key:" "$TEMP_DIR/key.txt" | awk '{print $4}')

# ダミーの secrets.yaml を元のファイルから自動生成する
grep '^[a-z0-9_]\+:' terraform/secrets.yaml | grep -v '^sops:' | while read -r line; do
  key=$(echo "$line" | cut -d: -f1)
  if [[ "$key" =~ "endpoint" ]] || [[ "$key" =~ "url" ]]; then
    echo "$key: \"https://dummy.example.com\""
  elif [[ "$key" =~ "token" ]] || [[ "$key" =~ "key" ]] || [[ "$key" =~ "password" ]] || [[ "$key" =~ "secret" ]]; then
    # 40文字のダミー値（Cloudflare API Tokenなどの制限に対応）
    echo "$key: \"0000000000000000000000000000000000000000\""
  else
    echo "$key: \"dummy\""
  fi
done > "$TEMP_DIR/dummy_secrets.yaml"

# ダミーの secrets.yaml を一時鍵で暗号化
sops --config /dev/null --encrypt --age "$PUBKEY" "$TEMP_DIR/dummy_secrets.yaml" > "$TEMP_DIR/secrets.yaml.enc"

# クリーンアップ処理の登録 (trap)
cleanup() {
  echo "Restoring original secrets.yaml..."
  if [ -f "terraform/secrets.yaml.orig" ]; then
    mv "terraform/secrets.yaml.orig" "terraform/secrets.yaml"
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# 本物のファイルを退避し、暗号化したダミーを配置
if [ -f "terraform/secrets.yaml" ]; then
  mv "terraform/secrets.yaml" "terraform/secrets.yaml.orig"
fi
cp "$TEMP_DIR/secrets.yaml.enc" "terraform/secrets.yaml"

# 一時秘密鍵を環境変数に設定して Terragrunt 検証を実行
export SOPS_AGE_KEY=$(grep -v "#" "$TEMP_DIR/key.txt")

echo "Running terragrunt init & validate modules..."
# terragrunt.hcl が存在するディレクトリを動的に検索する
target_dirs=()
while read -r file; do
  target_dirs+=("$(dirname "$file")")
done < <(find terraform -name "terragrunt.hcl" -not -path "*/.terragrunt-cache/*" | sort)

for dir in "${target_dirs[@]}"; do
  echo "Validating Terragrunt module: $dir"
  (
    cd "$dir"
    # すでに初期化されている場合は init をスキップして高速化する
    if [ ! -d ".terraform" ]; then
      terragrunt init -backend=false
    fi
    terragrunt validate
  )
done

echo "🎉 All Terraform validations passed!"
