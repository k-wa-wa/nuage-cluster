---
name: modify-nix-host
description: Reference of commands and techniques for changing, validating, applying, and debugging NixOS host configurations (nix/hosts, nix/modules, flake.nix).
---

# NixOS ホスト資材の変更

`nix/` 配下 (hosts, modules, flake.nix) を変更する際に使う手段のカタログ。新規クラスタの構築フロー全体は [[deploy-lxc-middleware]] を参照。

## 構成

- `nix/flake.nix`: 全ホストの `nixosConfigurations` 定義。新規ホストは `specialArgs` (`hostName`) でホスト名を渡す
- `nix/hosts/<name>/`: ホストごとの `configuration.nix`・ミドルウェア定義・`secrets.yaml` (SOPS)
- `nix/hosts/base-lxc` / `base-vm`: LXC / VM のベースイメージ構成
- `nix/modules/common.nix`: 共通モジュール
- シークレットの配線は [[sops-secrets]] を参照

## ローカル検証

```bash
# 評価エラーの検出 (ビルドせず確認)
nix build ./nix#nixosConfigurations.<host>.config.system.build.toplevel --dry-run

# flake input の更新
nix flake update nix-config --flake ./nix
```

## 適用手段

基本経路は master へ push → `system.autoUpgrade` が起動時 (30秒後) + daily で自動適用 (LXC / VM 共通)。

```bash
# 手動での即時適用 (ssh_config のホスト名が使える)
nixos-rebuild switch --flake ./nix#lb-1 --target-host lb-1 --use-remote-sudo

# push 済みの内容を即時反映させたい場合 (対象ノード上で)
ssh lb-1 "sudo systemctl start nixos-upgrade.service"
ssh lb-1 "journalctl -u nixos-upgrade.service -f"
```

`nix/` を master に push すると GitHub Actions (`nix-images.yaml`) が LXC ベースイメージをビルドし GitHub Release (`nix-images-lxc`) に公開する。

## push 前のデバッグ用一時適用

コミットせずにリモートで検証したい場合の手段:

```bash
# ローカルの変更をノードへ同期
rsync -avz --exclude=".git" ./nix/ <host>:/tmp/nix/

# ノード上で一時適用 (eval キャッシュをバイパス)
ssh <host> "sudo nixos-rebuild switch --flake /tmp/nix#<hostname> --option eval-cache false"
```

検証が済んだらソースを確定させ、必ず GitOps 経路 (push → autoUpgrade / 手動 rebuild) で本適用する。git 操作は行わず、ユーザーに依頼すること。

## デバッグ手段

```bash
ssh <host> "systemctl status <service>"
ssh <host> "journalctl -u <service> -n 50 --no-pager"
ssh <host> "journalctl -u nixos-upgrade.service -n 50 --no-pager"
```

## 注意点・既知の罠

- autoUpgrade は flake を tarball (`https://github.com/k-wa-wa/nuage-cluster/archive/master.tar.gz?dir=nix`) で取得する。GitHub rate limit 対策として nix-daemon が `/var/lib/nix-provisioning/access-tokens-env` のトークンを読み込む。rate limit エラー時はこのファイルの存在を確認する
- sops-nix の復号失敗時は `/var/lib/nix-provisioning/sops-key` の存在を確認 (PVE ホストの `/var/lib/pve/<host>/` を mount。配置は `terraform/pve/hosts-secrets`)
- `/run/<middleware>` 等のディレクトリ不在でソケット・PID ファイル作成に失敗しクラッシュすることがある。配置先を `/tmp` 等に退避させる
- NixOS モジュールが生成する設定ファイル (YAML 等) の属性ネストがミドルウェアの期待と合わないことがある。生成物を直接開いて確認する
- loadbalancer の keepalived は nopreempt 設定。VIP の動きを検証する際は state 遷移 (MASTER/BACKUP) のログを確認する
