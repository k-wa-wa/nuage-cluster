---
name: deploy-lxc-middleware
description: Workflow for defining, deploying, debugging, and verifying NixOS LXC middleware on Proxmox using Terraform.
---

# NixOS LXC Middleware Deployment and Verification

このスキルは、NixOS + Terraform を使用して Proxmox LXC 上にミドルウェア（PostgreSQL、MinIO など）を構築し、検証からトラブルシューティング、本番適用までの標準ワークフローを定義する。

---

## 1. 開発・デプロイフロー

新しいクラスタの定義から本番適用までは、以下のタイムラインに沿って実行する。

### フェーズ 1: 設計と実装 (AI)
1. **NixOS 設定の定義**:
   `nix/hosts/<name>/` ディレクトリを作成し、以下の設定ファイルを配置する。
   - `configuration.nix`: 基本OS構成、および `<middleware>.nix`, `keepalived.nix` 等のインポート。
   - `<middleware>.nix`: ミドルウェアの定義（データディレクトリ、ポート、認証等）。
   - `secrets.yaml`: 平文のシークレットテンプレート（そのまま使用しても問題ないようにランダム値をセットする）。
2. **flake.nix の更新**:
   `nix/flake.nix` に各クラスタノードの configuration 定義を追加する。
   - 評価時の循環参照を防ぐため、`specialArgs`（`hostName`）を用いて各ノードにホスト名を明示的に渡す。
3. **.sops.yaml へのルール追加**:
   プロジェクトルートにある `.sops.yaml` に対し、新規作成する `secrets.yaml` 用のパスルールを追加する。
4. **Terraform 定義の作成**:
   `terraform/vpc/zone-xxx/`（対象のゾーンディレクトリ）にて、対象クラスタの VM / LXC リソースを定義した `.tf` ファイルを作成する。
   - 各ノードの IP アドレスを決定し、既存の IP と重複していないことを確認する。
5. **ローカルビルド検証**:
   NixOS の構成に文法エラーなどがないか、ローカルで `nix build` ドライランを実行して検証する。

### フェーズ 2: ユーザーによる初期適用 (User)

ユーザーに以下の操作をまとめて依頼する。

1. **シークレット値の編集**: `secrets.yaml`（ダミー値）を、本番用の実際の機密情報に書き換える。
2. **SOPSによる暗号化**:
   > [!IMPORTANT]
   > AIアシスタントは `sops` コマンドによる暗号化・復号操作を実行しない。必ずユーザー自身が以下のコマンドを実行すること。
   > ```bash
   > sops -e -i nix/hosts/<name>/secrets.yaml
   > ```
3. **Gitへのコミット & プッシュ**: 暗号化した `secrets.yaml` と設定ファイルをリモートリポジトリへ反映する。
4. **インフラの起動 (Terragrunt)**:
   > [!IMPORTANT]
   > AIアシスタントは `terragrunt apply` を実行しない。必ずユーザー自身が以下のコマンドを実行すること。
   > ```bash
   > terragrunt --terragrunt-working-dir <target-dir> apply
   > ```
   これにより、基本OSテンプレートから LXC コンテナが起動する（この段階ではミドルウェアは未適用）。

### フェーズ 3: 動作検証とデバッグ (AI)

コンテナ起動後、設定が正常に機能するか検証し、問題があればデバッグ・修正を繰り返す。

1. **正常稼働の検証**:
   サービスが正常に起動し、想定通りの仕様（VIP、接続疎通、フェイルオーバー等）を満たすか確認する。
   - **サービスのステータス確認**: `systemctl status <service>`
   - **ログ確認**: `journalctl -u <service> -n 50 --no-pager`
2. **問題発生時のデバッグ**:
   疎通エラーやサービス起動失敗が発生した場合は、コンテナ内でログを確認して原因を特定する。
   - **よくあるエラーと対策**:
     - *Unix ソケット等の作成先ディレクトリ不在*: `/run/<middleware>` などのディレクトリが存在しないため、ソケット作成やPIDファイル作成に失敗しクラッシュする。設定内のソケット配置先や一時ディレクトリの指定を `/tmp` などに退避させる。
     - *認証情報のパースエラー (KeyError)*: NixOSモジュールが生成する YAML 設定ファイルを直接開き、属性のネスト構造がミドルウェアの期待する構造と合致しているか確認する。
3. **コード修正とローカル変更の同期**:
   発見された不具合に対しローカルのコードを修正し、`rsync` を用いてコンテナの `/tmp/nix` へ変更を同期する。
   ```bash
   rsync -avz -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i .ssh/id_ed25519_nixos" --exclude=".git" ./nix/ nixos@<ip-address>:/tmp/nix/
   ```
4. **一時適用**:
   対象ノードに SSH でログインし、キャッシュをバイパスして一時適用する。
   ```bash
   sudo nixos-rebuild switch --flake /tmp/nix#<hostname> --option eval-cache false
   ```
5. **デバッグループ (2〜4の繰り返し)**:
   問題が完全に解消し、1の正常稼働の検証が成功するまで 2〜4 のサイクルを繰り返す。

### フェーズ 4: 最終デプロイ適用と動作確認 (User / AI)

検証完了後、以下の手順で本番適用と最終確認を実行する。

1. **確定版ソースコードのコミット・プッシュ (User)**:
   ユーザーに、最終版のソースコードを git commit & push するよう依頼する。
2. **自動アップグレードのトリガー (AI)**:
   ユーザーのプッシュ完了後、AIが各ノードに SSH 接続し、自動アップグレードサービスを実行してリモートの master から最新 flake が正常に適用されるか確認する。
   ```bash
   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i .ssh/id_ed25519_nixos nixos@<ip-address> "sudo systemctl start nixos-upgrade.service"
   ```
3. **最終動作確認 (AI)**:
   アップグレード完了後、AIが各種サービスの起動状況、VIP の割り当て、およびエンドポイント疎通を最終テストし、構築完了とする。
   ```bash
   # アップグレードログの追跡
   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i .ssh/id_ed25519_nixos nixos@<ip-address> "journalctl -u nixos-upgrade.service -n 50 --no-pager"
   ```
