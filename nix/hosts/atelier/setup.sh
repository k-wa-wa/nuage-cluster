#!/usr/bin/env bash
# atelier の nixos ユーザーで実行し、更新の速いツールを ~/.local に入れ、nuage のリポジトリを最新の master に揃える。
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

# 前もってクローンし、Orca に登録しておくリポジトリ (k-wa-wa/<名前>)。
# nuage-workspace の AGENTS.md の地図と揃える。nuage-autopilot4 は autopilot-server でだけ使う旧版なので入れない。
REPOS=(
  nuage-workspace
  nuage-cluster
  nuage-monitoring-stack
  pechka
  bare-web-proxy
  nuage-home
  nuage-usage-ledger
  cicerone3270
  nuage-autopilot5
  nix-config
)

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
# ~/.config/git/config は home-manager (nix-config) が読み取り専用で置く。
# ~/.gitconfig が無いと --global はそちらへ書こうとして失敗するので、書き先を明示する。
git config --file "$HOME/.gitconfig" user.name "$login"
git config --file "$HOME/.gitconfig" user.email "${id}+${login}@users.noreply.github.com"
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

# リポジトリの登録は起動した Orca に対して行うので、受け付けられるようになるまで待つ。
for _ in $(seq 60); do
  orca-ide status --json 2>/dev/null | jq -e '.result.runtime.state == "ready"' >/dev/null && break
  sleep 1
done
if ! orca-ide status --json 2>/dev/null | jq -e '.result.runtime.state == "ready"' >/dev/null; then
  echo "Orca が 60 秒たっても起動しない。journalctl --user -u orca-serve を確かめること" >&2
  exit 1
fi

echo "== リポジトリ"
# ghq の置き場所へクローンして Orca に登録し、master を origin に揃える。
# Orca のワークスペースは別の worktree に作るので、本体は master のまま変更を置かない前提である。
# 前提から外れたリポジトリは作業を消さないよう fetch だけにとどめ、最後にまとめて知らせて失敗させる。
skipped=()
for name in "${REPOS[@]}"; do
  orca-get "k-wa-wa/$name" >/dev/null
  path="$(ghq root)/github.com/k-wa-wa/$name"
  git -C "$path" fetch --prune --quiet origin
  branch=$(git -C "$path" branch --show-current)
  if [ "$branch" != master ]; then
    skipped+=("$name: master ではなく ${branch:-detached HEAD} を開いている")
  elif [ -n "$(git -C "$path" status --porcelain)" ]; then
    skipped+=("$name: 未 commit の変更がある")
  elif [ -n "$(git -C "$path" rev-list origin/master..master)" ]; then
    skipped+=("$name: master に origin に無い commit がある")
  else
    git -C "$path" merge --ff-only --quiet origin/master
    echo "$name $(git -C "$path" log -1 --format='%h %s')"
  fi
done
if [ "${#skipped[@]}" -gt 0 ]; then
  echo "最新の master にできなかったリポジトリがある (fetch は済み):" >&2
  printf '  %s\n' "${skipped[@]}" >&2
  exit 1
fi
