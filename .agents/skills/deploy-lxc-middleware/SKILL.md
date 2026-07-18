---
name: deploy-lxc-middleware
description: Workflow for defining, deploying, debugging, and verifying NixOS LXC middleware on Proxmox using Terraform.
---

# NixOS LXC ミドルウェアクラスタの構築

NixOS + Terraform で Proxmox LXC 上にミドルウェア (PostgreSQL, MinIO 等) のクラスタを新規構築する際のフロー。個別の手段・コマンドは [[modify-nix-host]] / [[modify-terraform]] / [[sops-secrets]] を参照し、ここではフェーズの順序と新規構築に固有の作業のみ定義する。

## フェーズ 1: 設計と実装 (AI)

1. **NixOS 設定の定義**: `nix/hosts/<name>/` を作成する。
   - `configuration.nix`: 基本OS構成と `<middleware>.nix`, `keepalived.nix` 等のインポート
   - `<middleware>.nix`: ミドルウェアの定義 (データディレクトリ、ポート、認証等)
   - `secrets.yaml`: 平文のシークレットテンプレート (そのまま使用しても問題ないランダム値をセットする)
2. **flake.nix の更新**: 各クラスタノードの configuration を追加する。評価時の循環参照を防ぐため、`specialArgs` (`hostName`) で各ノードにホスト名を明示的に渡す。
3. **`.sops.yaml` へのルール追加**: [[sops-secrets]]
4. **Terraform 定義の作成**: 対象ゾーンに LXC リソースを定義し、IP 重複確認と `.ssh/gen-keys.sh` への追記を行う。[[modify-terraform]]
5. **ローカルビルド検証**: `nix build` ドライランで評価エラーを検出する。[[modify-nix-host]]

## フェーズ 2: ユーザーによる初期適用 (User)

ユーザーに以下をまとめて依頼する。

1. `secrets.yaml` を本番値に書き換えて SOPS 暗号化 ([[sops-secrets]])
2. git commit & push
3. `terragrunt apply` でインフラ起動 ([[modify-terraform]])。基本OSテンプレートから LXC が起動する (この段階ではミドルウェア未適用)

## フェーズ 3: 動作検証とデバッグ (AI)

コンテナ起動後、サービスが仕様 (VIP、接続疎通、フェイルオーバー等) を満たすまでデバッグループを回す。

- 検証・デバッグ・rsync + `/tmp/nix` からの一時適用の手段は [[modify-nix-host]] を参照
- 問題が解消するまで「ソース修正 → 一時適用 → 検証」を繰り返す

## フェーズ 4: 最終適用と動作確認 (User / AI)

1. **確定版の commit & push (User)**
2. **本適用の確認 (AI)**: 各ノードで `nixos-upgrade.service` をトリガーし、リモートの master から最新 flake が正常に適用されることを確認する ([[modify-nix-host]])
3. **最終動作確認 (AI)**: サービス起動状況・VIP 割り当て・エンドポイント疎通をテストし、構築完了とする
