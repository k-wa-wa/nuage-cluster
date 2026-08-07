#!/usr/bin/env bash
# lm-server 上で facefusion (https://docs.facefusion.io) をセットアップするスクリプト。
#
# 前提: 本リポジトリの nix/hosts/lm-server/configuration.nix が適用済みであること
#   (facefusion-env FHS サンドボックス / ROCm ランタイムライブラリ / ffmpeg が導入されるのは Nix 側の責務)。
#   未適用の場合は先に以下を実行する。
#     nixos-rebuild switch --flake ./nix#lm-server --target-host nixos@192.168.5.222 --use-remote-sudo
#
# 使い方 (lm-server 上で実行、再実行しても安全):
#   bash setup-facefusion.sh
#
# miniconda / pip で入れるバイナリ (onnxruntime の MIGraphX Execution Provider 等) が要求する
# glibc / ROCm ランタイムの世代を合わせるため、facefusion-env (buildFHSEnv) の中で自分自身を
# 再実行する。
# 素の NixOS でも /lib64/ld-linux-x86-64.so.2 自体は常に存在する ("動的リンク実行ファイルは
# 動かせない" と案内する stub-ld へのシンボリックリンク)。存在有無ではなく、実体が本物の glibc
# (facefusion-env = buildFHSEnv の中でのみ真) か stub-ld (素の NixOS) かで判定する。
loader_target="$(readlink -f /lib64/ld-linux-x86-64.so.2 2>/dev/null || true)"
if [[ "$loader_target" != *-glibc-*/lib/ld-linux-x86-64.so.2 ]]; then
  if ! command -v facefusion-env >/dev/null 2>&1; then
    echo "facefusion-env が見つからない。nixos-rebuild switch で lm-server 構成をまだ適用していない可能性がある。" >&2
    exit 1
  fi
  exec facefusion-env "$0" "$@"
fi

set -euo pipefail

FACEFUSION_HOME="${FACEFUSION_HOME:-$HOME/facefusion}"
MINICONDA_HOME="${MINICONDA_HOME:-$HOME/miniconda3}"
CONDA_ENV_NAME="facefusion"

# 同一 GPU (AMD, gfx バージョン未サポート機) 向けの override。
# ollama (services.ollama.environmentVariables) と同じ値を使う。
export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"

echo "==> Miniconda"
if [ ! -d "$MINICONDA_HOME" ]; then
  tmp_installer="$(mktemp -t miniconda-XXXXXX.sh)"
  curl -fsSL -o "$tmp_installer" https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
  bash "$tmp_installer" -b -p "$MINICONDA_HOME"
  rm -f "$tmp_installer"
else
  echo "既に導入済み: $MINICONDA_HOME"
fi

source "$MINICONDA_HOME/etc/profile.d/conda.sh"
conda init --all >/dev/null

# Anaconda 既定チャンネル (pkgs/main, pkgs/r) は ToS 同意が必須のため非対話で受諾する
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >/dev/null
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r >/dev/null

echo "==> conda env: $CONDA_ENV_NAME"
if ! conda env list | grep -q "^${CONDA_ENV_NAME} "; then
  conda create --yes --name "$CONDA_ENV_NAME" python=3.12 pip=25.0
else
  echo "既に作成済み: $CONDA_ENV_NAME"
fi

conda activate "$CONDA_ENV_NAME"

echo "==> ROCm 向けコンパイラ (conda-forge::gcc)"
conda install --yes conda-forge::gcc=15.2.0

echo "==> facefusion リポジトリ"
if [ ! -d "$FACEFUSION_HOME" ]; then
  git clone https://github.com/facefusion/facefusion "$FACEFUSION_HOME"
else
  git -C "$FACEFUSION_HOME" pull --ff-only
fi

cd "$FACEFUSION_HOME"

echo "==> facefusion 本体 (MIGraphX backend)"
python install.py migraphx

conda deactivate
conda activate "$CONDA_ENV_NAME"

cat <<EOF

セットアップ完了。起動するには (facefusion-env の中で実行すること):

  facefusion-env
  source "$MINICONDA_HOME/etc/profile.d/conda.sh"
  conda activate $CONDA_ENV_NAME
  cd "$FACEFUSION_HOME"
  HSA_OVERRIDE_GFX_VERSION=$HSA_OVERRIDE_GFX_VERSION python facefusion.py run --open-browser

Web UI は既定で localhost のみ bind されるため、手元の端末から SSH トンネルでアクセスする。
  ssh -L 7860:localhost:7860 nixos@192.168.5.222
EOF
