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
| NixOS | `nix/hosts/<host>/secrets.yaml` | sops-nix。各ホストの SSH ホスト鍵 `/var/lib/nix-provisioning/ssh_host_ed25519_key` を Age 鍵として使い復号する。鍵は `scripts/gen-host-keys.sh` で作って `terraform/pve/hosts-secrets/host-keys.yaml` に置き、`terraform/pve/hosts-secrets` が PVE ホストに配置したファイルを LXC に mount する (bluray-extractor は cloud-config で置く) |
| Kubernetes | デプロイ対象リポジトリ内の SOPS 暗号化マニフェスト | argocd-vault-plugin (AVP, sops モード) が Argo CD 同期時に復号。鍵は argocd namespace の `sops-age-key` Secret |

## `.sops.yaml` (リポジトリルート)

- 鍵は `admin_key` (管理者、`~/.config/sops/age/keys.txt`)、`master_key` (紙に控えたオフラインの鍵。復旧のときだけ使う)、ホストごとの鍵 (`.ssh/known_hosts` の公開鍵から `ssh-to-age` で作る)、`argocd_key`
- 新しい `secrets.yaml` を作る場合は `creation_rules` に `path_regex` ルールを追加する。どのルールにも `admin_key` + `master_key` を入れ、NixOS ホスト用はそのファイルを読むホストの鍵を加える
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
- **NixOS**: `ssh <host> "sudo ls -l /var/lib/nix-provisioning/ssh_host_ed25519_key"`。無ければ PVE ホスト側の `/var/lib/pve/<host>/` と `terraform/pve/hosts-secrets` の適用状況を確認。鍵が `.ssh/known_hosts` と一致するか (`sudo ssh-keygen -y -f <鍵>`)、`.sops.yaml` のルールにそのホストの鍵が含まれているかも確認
- **Kubernetes**: `kubectl get secret sops-age-key -n argocd` の存在確認。消えていれば `scripts/apply-apps.sh` 内の手順で再登録。AVP のログは `kubectl -n argocd logs deploy/argocd-repo-server -c avp`

## 関連ドキュメント

鍵の管理区分・ローテーション手順は `docs/secrets-management.md` を参照。
