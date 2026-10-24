#!/usr/bin/env bash
# atelier の nixos ユーザーで実行し、更新の速いツールを ~/.local に入れる。
# 初回にも更新にも使う。何度実行してもよい。
#
#   ~/setup.sh                          # すべて最新にする
#   ORCA_VERSION=1.4.238 ~/setup.sh     # Orca の版を指定する (スマホ・Mac の Orca と揃えるとき)
#
# 事前に /var/lib/atelier/secrets.env へ GH_TOKEN=<bot-wa-wa の token> を置いておく。

set -euo pipefail

SECRETS=/var/lib/atelier/secrets.env
ORCA_ROOT="$HOME/.local/share/orca-ide"
BIN="$HOME/.local/bin"

if [ "$(id -u)" -eq 0 ]; then
  echo "root ではなく nixos ユーザーで実行すること" >&2
  exit 1
fi

if [ -r "$SECRETS" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$SECRETS"
  set +a
fi
if [ -z "${GH_TOKEN:-}" ]; then
  echo "$SECRETS に GH_TOKEN が無い。bot の token を置いてから実行すること" >&2
  exit 1
fi

mkdir -p "$BIN"

echo "== エージェント CLI"
curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
curl -fsSL https://gh.io/copilot-install | bash

# Orca から起動したときに「権限確認を飛ばしてよいか」の初回確認で止まらないようにする。
# settings.json は Orca がフックを書き込むので、nix で管理せずキーだけを足す。
settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"
[ -s "$settings" ] || echo '{}' >"$settings"
jq '.skipDangerousModePermissionPrompt = true' "$settings" >"$settings.tmp"
mv "$settings.tmp" "$settings"

echo "== git の名前 (bot)"
login=$(gh api user --jq .login)
id=$(gh api user --jq .id)
# 人間の token を置くと、エージェントの書き込みが人間の発言と区別できなくなる。
if [ "$login" = "k-wa-wa" ]; then
  echo "GH_TOKEN が人間 (k-wa-wa) のもの。bot-wa-wa の token に差し替えること" >&2
  exit 1
fi
git config --global user.name "$login"
git config --global user.email "${id}+${login}@users.noreply.github.com"
echo "$login"

echo "== Orca"
version="${ORCA_VERSION:-$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest | jq -r .tag_name)}"
version="${version#v}"
dest="$ORCA_ROOT/$version"
if [ -x "$dest/orca-ide" ]; then
  echo "$version は導入済み"
else
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  curl -fsSL -o "$work/orca.deb" \
    "https://github.com/stablyai/orca/releases/download/v${version}/orca-ide_${version}_amd64.deb"
  (cd "$work" && ar x orca.deb && mkdir data && tar -xf data.tar.* -C data)
  mkdir -p "$ORCA_ROOT"
  rm -rf "$dest"
  mv "$work/data/opt/Orca" "$dest"
  echo "$version を入れた"
fi
ln -sfn "$dest" "$ORCA_ROOT/current"
ln -sfn "$ORCA_ROOT/current/resources/bin/orca-ide" "$BIN/orca-ide"

# 使っている版以外を消す。
find "$ORCA_ROOT" -mindepth 1 -maxdepth 1 -type d ! -name "$version" -exec rm -rf {} +

# 本体だけを再起動する。セッションは KillMode=process で残る。
systemctl --user daemon-reload
systemctl --user restart orca-serve
systemctl --user --no-pager status orca-serve | head -5

if ! tailscale status >/dev/null 2>&1; then
  echo
  echo "Tailscale に未参加。次を実行してから Orca を接続すること:"
  echo "  sudo tailscale up"
fi
