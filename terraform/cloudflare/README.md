# Cloudflare インフラ管理 (Terragrunt / Terraform)

本ディレクトリでは、Cloudflare 上の DNS レコード、Zero Trust Tunnel (ハニーポット公開用)、およびハニーポット宛てのエッジ素通し設定をコード管理する。

エッジ素通し設定は、Cloudflare エッジの既定の保護（Browser Integrity Check・Security Level・マネージド WAF・Bot Fight Mode・AI クローラーのブロック）が攻撃トラフィックを転送前に遮断し、ハニーポットまで届かなくなるのを防ぐためのものである。WAF のカスタムルール（skip）は囮ドメイン宛てのみに効く。Bot 設定はゾーン全体の設定だが、proxied なレコードは囮ドメインの CNAME だけなので、実際に影響を受けるのはハニーポットのみである。

## 囮ドメイン

ハニーポットに転送する囮のサブドメインは、`main.tf` の `local.honeytrap_hostnames` で一元管理する。Tunnel の転送ルール・CNAME レコード・エッジ素通しのルールは、すべてこの一覧から作られる。

| ドメイン |
| :--- |
| `staging-ext.wpcapp.net` |
| `dev-portal.wpcapp.net` |
| `admin-stg.wpcapp.net` |
| `jenkins-dev.wpcapp.net` |
| `vpn-staging.wpcapp.net` |

- 個別の CNAME はワイルドカード A レコード（`*.wpcapp.net`）より優先されるため、社内向けのサービス名には影響しない。社内で使っている名前（`pechka`・`grafana` 等）を囮に使ってはならない。
- 一覧を変えたら、nuage-honeytrap の `k8s/base/registrar-cronjob.yaml`（`REGISTRAR_DOMAINS`、urlscan.io への登録対象）も揃える。名前解決できないドメインは登録 Job が失敗するので、こちらを先に apply する。

## 1. 認証情報管理ポリシー

外部システムの機密情報（API トークン）を Git リポジトリに残さないポリシーのため、SOPS 管理を廃止し **ローカル平文ファイル (`secrets.local.yaml`) による一時利用方式** を採用している。

- `secrets.local.yaml` は `.gitignore` に登録されており、Git にコミットされない。
- 作業時のみトークンを記入し、作業完了後はトークンを失効させるかファイルをクリアする。

## 2. API トークン発行と必要スコープ

Tunnel（アカウントリソース）と DNS・WAF・Bot 設定（ゾーンリソース）を同時に管理するため、**My Profile（マイプロフィール） > API Tokens** から Custom Token を作成する。

### 必要スコープ (Permissions)
| リソース種別 | 権限レベル | 用途 |
| :--- | :--- | :--- |
| **Zone > DNS** | **Edit** | 囮ドメインの CNAME および内部 DNS レコードの作成 |
| **Zone > Zone** | **Read** | ゾーン情報の参照 |
| **Zone > Zone WAF** | **Edit** | ハニーポット宛てを素通しする WAF カスタムルール（skip）の作成 |
| **Zone > Bot Management** | **Edit** | Bot Fight Mode・AI クローラーのブロックの無効化 |
| **Account > Cloudflare Tunnel** | **Edit** | ハニーポット公開用 Zero Trust Tunnel の作成・設定 |

- **Account Resources**: 対象アカウント（または All accounts）
- **Zone Resources**: `wpcapp.net`（または All zones）
- **TTL**: 7 日間など一時的な有効期限を設定することを推奨

![API Token Permissions](images/api-token-permissions.png)

## 3. リリース手順 (疎通までのステップ)

### Step 1: ローカル秘密ファイルと ID の設定
1. トークン設定ファイルを作成:
   ```bash
   cp secrets.local.yaml.example secrets.local.yaml
   # secrets.local.yaml を開き、cloudflare_api_token に発行したトークンを記入
   ```
2. `main.tf` の先頭プレースホルダーに実際の ID を記入:
   ```hcl
   locals {
     account_id = "..." # Cloudflare の Account ID
     zone_id    = "..." # wpcapp.net の Zone ID
   }
   ```

### Step 2: Terragrunt の適用
```bash
# 差分確認 (precondition ガードを通過することを確認)
terragrunt --working-dir terraform/cloudflare plan

# 適用 (Tunnel・CNAME レコード・エッジ素通し設定を作成)
terragrunt --working-dir terraform/cloudflare apply
```

> [!NOTE]
> ゾーンにカスタムルールのエントリポイント ruleset（`http_request_firewall_custom`）がすでにある場合（ダッシュボードでカスタムルールを作ったことがある等）、`cloudflare_ruleset.honeytrap_bypass` の作成は失敗する。その場合は既存の ruleset を取り込んでから再度 apply する。取り込んだ ruleset の既存ルールは、この定義で置き換わる。
> ```bash
> terragrunt --working-dir terraform/cloudflare import cloudflare_ruleset.honeytrap_bypass zones/<zone_id>/<ruleset_id>
> ```

### Step 3: Tunnel トークンの取得
```bash
terragrunt --working-dir terraform/cloudflare output -raw honeytrap_tunnel_token
```

### Step 4: nuage-honeytrap への配線とデプロイ
1. `nuage-honeytrap` 側の `k8s/overlays/prod/secrets/prod-secrets.yaml` に取得したトークンを設定し、SOPS 暗号化してコミット。
2. 両リポジトリの PR をマージし、Argo CD が自動同期して完了。
