---
name: deploy-lxc-middleware
description: Workflow for defining, deploying, debugging, and verifying NixOS LXC middleware on Proxmox using Terraform.
---

# NixOS LXC Middleware Deployment and Verification

このスキルは、NixOS + Terraform を使用して Proxmox LXC 上にミドルウェア（PostgreSQL、MinIO など）を構築し、検証からトラブルシューティング、高可用性（HA/VIP）テストを行うための標準ワークフローを定義する。

---

## 1. 開発・デプロイフロー

新しいクラスタの定義から適用までは、以下の順番で実行する。

### ステップ 1: NixOS 設定の定義
1. `nix/hosts/<name>/` ディレクトリを作成する。
2. 以下の設定ファイルを定義・配置する。
   - `configuration.nix`: 基本OS構成。
   - `<middleware>.nix`: ミドルウェアの定義（データディレクトリ、ポート、認証等）。
   - `secrets.yaml`: 平文のシークレットテンプレート（ダミー値）。
3. `nix/flake.nix` に各クラスタノード（例: `pg-cluster-1`, `2`, `3`）の configuration 定義を追加する。
   - 評価時の循環参照を防ぐため、`specialArgs`（`hostName`）を用いて各ノードにホスト名を明示的に渡す。

### ステップ 2: Terraform / Terragrunt によるリソース構築
1. `terraform/vpc/zone-xxx/`（対象のゾーンディレクトリ）にて、対象クラスタの VM / LXC リソースを定義した `.tf` ファイルを作成する。
   - 各ノードの IP アドレスを決定し、既存の IP と重複していないことを確認する。
   - `nix-lxc` モジュールを使用し、引数 `sops_key` に SOPS ファイルから読み込んだ秘密鍵を渡す。

### ステップ 3: .sops.yaml へのルール追加とビルド検証
1. プロジェクトルートにある `.sops.yaml` に対し、新規作成する `secrets.yaml` 用のパスルールを追加する。
   ```yaml
     - path_regex: nix/hosts/<name>/secrets\.yaml$
       key_groups:
         - age:
             - *admin_key
             - *lb_key
   ```
2. NixOS の構成に文法エラーなどがないか、`nix build path:.#nixosConfigurations.<hostname>.config.system.build.toplevel --dry-run` を実行して検証する。

### ステップ 4: ユーザーによるSOPS暗号化とデプロイ適用
ユーザーに以下の操作をまとめて依頼する。

1. `secrets.yaml`（ダミー値）を、本番用の実際の機密情報に書き換える。
2. SOPS コマンドを用いて、作成した `secrets.yaml` を暗号化する。
   > [!IMPORTANT]
   > AIアシスタントは `sops` コマンドによる暗号化・復号操作を実行しない。必ずユーザー自身が以下のコマンドを実行すること。
   > ```bash
   > sops -e -i nix/hosts/<name>/secrets.yaml
   > ```
3. 暗号化された `secrets.yaml` とその他の設定ファイルを git commit & push する。
   > [!IMPORTANT]
   > LXCノードは `system.autoUpgrade` サービスにより自動で master リポジトリから最新の Flake を引っ張って適用（Pull型デプロイ）するため、変更は常にリモート（GitHub等）に存在する必要がある。
4. `terragrunt --terragrunt-working-dir <target-dir> apply` を実行し、インフラを適用する。

**ここまでの ステップ4 1~4 の操作はユーザーが行う操作であり、AIアシスタントは勝手に実行しないこと。**

---

## 2. デバッグとトラブルシューティング (SSH接続)

デプロイ完了後、ミドルウェアが正常に起動しない場合は、各ノードに SSH で接続して以下の手順でデバッグを行う。

```bash
ssh -i .ssh/id_ed25519_nixos nixos@<ip-address>
```

操作端末から繋がる IP アドレスは `192.168.5.0/24` のみであるため、デバッグ時には必要に応じて LXC に一時 IP アドレスを追加する。

### よくあるエラーと対策

#### Unix ソケット等の作成先ディレクトリ不在
- **症状**: `/run/<middleware>` などのディレクトリが存在しないため、ソケット作成やPIDファイル作成に失敗しクラッシュする。
- **対策**: NixOS LXC内でのディレクトリ自動作成制限に対応するため、設定内のソケット配置先や一時ディレクトリの指定を `/tmp` などに退避させる。

#### 認証情報のパースエラー (`KeyError`)
- **症状**: 起動スクリプトの実行中に `KeyError` などの例外が発生してクラッシュする。
- **対策**: NixOSモジュールが生成する YAML 設定ファイル（`/nix/store/*-patroni-*.yaml` など）を直接開き、属性のネスト構造が Patroni などのミドルウェアの期待する構造（例: `authentication` ブロックの下か直下か）と合致しているか確認する。

#### 変更適用時のキャッシュ問題の回避
手動で `nixos-rebuild switch` を再実行する際、Nix の Flake 評価キャッシュ（eval-cache）により、ローカルでの変更が無視されることがある。キャッシュをバイパスして強制的に評価させるために以下を実行する。

```bash
sudo nixos-rebuild switch --flake /tmp/nix#<hostname> --option eval-cache false
```

---

## 3. 正常稼働およびフェイルオーバー（カオステスト）検証手順

構築完了後、以下のテストを実機で実施し、想定通りの冗長化と自動切り替えが機能しているか検証する。

### アップグレード動作確認
各ノードで `nixos-upgrade.service` を手動トリガーし、リモートの最新定義からクリーンにビルド・再起動されるか確認する。
```bash
sudo systemctl start nixos-upgrade.service
# 完了を待つ (systemctl status または journalctl で追跡)
journalctl -u nixos-upgrade.service -n 50 --no-pager
```
