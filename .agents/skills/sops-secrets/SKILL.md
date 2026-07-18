---
name: sops-secrets
description: Reference of how SOPS-encrypted secrets are wired into Terraform, NixOS (sops-nix), and Kubernetes (argocd-vault-plugin), and how to verify decryption failures.
---

# SOPS シークレットの配線と確認手段

シークレットは 3 層それぞれ別の仕組みで復号される。変更・調査時に使う手段のカタログ。

> [!IMPORTANT]
> AI は `sops` コマンドによる作成・編集・復号を実行しない (AGENTS.md)。平文テンプレートの作成までを行い、暗号化・値の設定はユーザーに依頼する。

## 3 層の配線

| 層 | ファイル | 復号の仕組み |
| :-- | :-- | :-- |
| Terraform | `terraform/secrets.yaml`, `terraform/truenas/secrets.yaml` | `terraform/root.hcl` が terragrunt 実行時に `sops_decrypt_file` で復号し provider に注入 |
| NixOS | `nix/hosts/<host>/secrets.yaml` | sops-nix。ノード上の Age 鍵 `/var/lib/nix-provisioning/sops-key` で復号 (`terraform/pve/hosts-secrets` が PVE ホストに配置したファイルを LXC に mount) |
| Kubernetes | デプロイ対象リポジトリ内の SOPS 暗号化マニフェスト | argocd-vault-plugin (AVP, sops モード) が Argo CD 同期時に復号。鍵は argocd namespace の `sops-age-key` Secret |

## `.sops.yaml` (リポジトリルート)

- 鍵は `admin_key` (管理者、`~/.config/sops/age/keys.txt`) と `lb_key` (ノード側) の 2 種
- 新しい `secrets.yaml` を作る場合は `creation_rules` に `path_regex` ルールを追加する。NixOS ホスト用は `admin_key` + `lb_key` の両方を指定する
- 受信者を変更した場合の再暗号化 (ユーザーに依頼): `sops updatekeys <file>`

## ユーザーに依頼するコマンド

```bash
sops <file>                            # 編集 (復号 → エディタ → 再暗号化)
sops -e -i nix/hosts/<name>/secrets.yaml   # 新規テンプレートの暗号化
sops updatekeys <file>                 # 受信者変更後の再暗号化
```

新規テンプレートを作る際は、そのまま使っても問題ないランダム値をセットしておく。

## 復号失敗時の確認手段

- **Terraform**: `terraform/secrets.yaml` に対象キーが存在するか、`.sops.yaml` のルールにマッチしているか確認
- **NixOS**: `ssh <host> "ls /var/lib/nix-provisioning/sops-key"`。無ければ PVE ホスト側の `/var/lib/pve/<host>/` と `terraform/pve/hosts-secrets` の適用状況を確認。`.sops.yaml` に `lb_key` が含まれているかも確認
- **Kubernetes**: `kubectl get secret sops-age-key -n argocd` の存在確認。消えていれば `scripts/apply-apps.sh` 内の手順で再登録。AVP のログは `kubectl -n argocd logs deploy/argocd-repo-server -c avp`

## 関連ドキュメント

鍵の管理区分・ローテーション手順は `docs/secrets-management.md` を参照。
