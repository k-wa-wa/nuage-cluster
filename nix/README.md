# NixOS Configurations

## 構成のデプロイ方法

### 1. 手動での即時適用 (ローカルからリモートへ適用)

ローカルマシンの変更を各サーバーに即座にデプロイする場合は、以下のコマンドを使用する。

```bash
# loadbalancer (例: lb-1)
nixos-rebuild switch --flake ./nix#lb-1 --target-host nixos@192.168.5.201 --use-remote-sudo

# dev-server (ローカル適用)
sudo nixos-rebuild switch --flake ./nix#dev-server

# lm-server
nixos-rebuild switch --flake ./nix#lm-server --target-host nixos@192.168.5.222 --use-remote-sudo
```

### 2. 初期セットアップ (nixos-anywhere を使用)

新規マシンの初期セットアップを行う場合:

```bash
# dev-server
nix run github:numtide/nixos-anywhere -- \
  --flake ./nix#base-vm \
  --target-host nixos@192.168.5.199

# lm-server
nix run github:numtide/nixos-anywhere -- \
  --flake ./nix#base-vm \
  --target-host nixos@192.168.5.222
```

### 3. GitOps による自動アップグレード
LXCコンテナ (loadbalancerなど) には `system.autoUpgrade` が設定されており、起動時および定期的にこのリポジトリから自動で最新の設定を取得して適用する。

#### 手動で自動アップグレードをトリガーする

コンテナ内で以下のコマンドを実行する:

```bash
sudo systemctl start nixos-upgrade.service
```

ログを確認する:

```bash
journalctl -u nixos-upgrade.service -f
```

## アップデート

```bash
# nix-config 入力などの更新
nix flake update nix-config --flake ./nix
```
