#!/usr/bin/env bash
set -euo pipefail

# atelier のエージェントが各 NixOS ホストへ agent ユーザー (nix/modules/agent-user.nix) として
# SSH で入るための鍵を Mac で作り、公開鍵を nix/modules/atelier-agent.pub に書き出し、
# 秘密鍵を atelier の /var/lib/atelier/agent_ed25519 に置く。
# atelier の ssh は /etc/ssh/ssh_config (nix/hosts/atelier/configuration.nix) でこの鍵を使う。
# kubeconfig (setup-autopilot-kubeconfig.sh) と同じくSOPSには載せず、このスクリプトで手動配置する。
# 何度実行してもよい。鍵を作り直すときは .ssh/keys/atelier-agent* を消してから実行する。
#
# 使い方: cd nuage-cluster && bash scripts/setup-atelier-ssh-key.sh [ホスト名 (既定: atelier)]

KEY_FILE=.ssh/keys/atelier-agent
PUB_FILE=nix/modules/atelier-agent.pub
REMOTE_PATH=/var/lib/atelier/agent_ed25519
HOST="${1:-atelier}"

if [ ! -f .ssh/ssh_config ] || [ ! -d nix/modules ]; then
  echo "Error: リポジトリルート (nuage-cluster) で実行する" >&2
  exit 1
fi

mkdir -p "$(dirname "${KEY_FILE}")"
if [ ! -f "${KEY_FILE}" ]; then
  ssh-keygen -q -t ed25519 -N "" -C atelier-agent -f "${KEY_FILE}"
  echo "鍵を ${KEY_FILE} に作った"
else
  echo "既存の鍵 ${KEY_FILE} を使う"
fi

# 公開鍵は秘密鍵から導く (.pub が古い・欠けている場合でも秘密鍵と食い違わない)。
echo "$(ssh-keygen -y -f "${KEY_FILE}" | cut -d' ' -f1,2) atelier-agent" > "${PUB_FILE}"
echo "公開鍵を ${PUB_FILE} に書いた (commit して push する)"

ssh -F .ssh/ssh_config "${HOST}" "install -m 600 /dev/null ${REMOTE_PATH}"
scp -F .ssh/ssh_config "${KEY_FILE}" "${HOST}:${REMOTE_PATH}"
ssh -F .ssh/ssh_config "${HOST}" "chmod 600 ${REMOTE_PATH} && ls -l ${REMOTE_PATH}"

echo "秘密鍵を ${HOST}:${REMOTE_PATH} に配置した"
