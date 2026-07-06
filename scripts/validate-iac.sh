#!/usr/bin/env bash

set -euo pipefail

# PATHの優先指定（Nixのパスも含める）
export PATH=$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH

echo "=== IaC Validation ==="

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

# ダミーの secrets.yaml テンプレート
cat <<EOF > "$TEMP_DIR/dummy_secrets.yaml"
proxmox_endpoint: "https://dummy.example.com"
proxmox_username: "dummy"
proxmox_password: "dummy"
cloudflare_api_token: "dummy"
cloudflare_account_id: "dummy"
lb_sops_key: "dummy"
EOF

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

echo "Running terragrunt init & validate on root_sops.hcl modules..."
# root_sops.hcl を使用しているモジュールのみを検証対象とする
# root.hcl を使用している未移行のモジュールは非推奨エラーになるためスキップ
target_dirs=(
  "terraform/vpc/zone-private-k8s"
  "terraform/pve/hosts"
  "terraform/vpc/zone-private"
)

for dir in "${target_dirs[@]}"; do
  echo "Validating Terragrunt module: $dir"
  (
    cd "$dir"
    # -backend=false で state を無視して初期化
    terragrunt init -backend=false
    terragrunt validate
  )
done

# 4. Nix Flake Check
echo "Running nix flake check..."
nix flake check ./nix

# 5. NixOS Build Dry-run (Linux Only)
if [ "$(uname -s)" = "Linux" ]; then
  echo "Running NixOS configurations dry-run build..."
  hosts=("base-vm" "dev-server" "lb-1" "lb-2" "lb-3" "egress-gateway" "lm-server")
  for host in "${hosts[@]}"; do
    echo "Dry-running build for host: $host"
    nix build ./nix#nixosConfigurations."$host".config.system.build.toplevel --dry-run
  done
else
  echo "Skipping NixOS build dry-run (Not on Linux)"
fi

echo "🎉 All IaC validations passed!"
