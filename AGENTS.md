# Nuage Cluster Workspace Rules

このファイルは、`nuage-cluster` リポジトリで動作する AI Agent 向けの動作ルールと前提条件を定義する。Agent は、コマンド実行やファイル編集の際、これらのルールを厳格に適用する必要がある。

## 1. コマンド実行時の環境変数とPATHの設定

- **PATHの優先指定**:
  このワークスペースで CLI ツール（`kubectl`, `talosctl`, `terragrunt` 等）を実行する際は、事前に以下のパスを設定する。
  ```bash
  export PATH=$HOME/.nix-profile/bin:$PATH
  ```

- **KUBECONFIGの指定**:
  Kubernetes関連のコマンド（`kubectl`, `kustomize`, `helm` など）を実行する際は、デフォルトで以下のパスを `KUBECONFIG` として使用する。
  ```bash
  export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig
  ```

- **ノードへのSSH接続**:
  `~/.ssh/config` が本リポジトリの `.ssh/ssh_config`（`.ssh/gen-keys.sh` が生成）を Include しているため、ホスト名だけで接続できる。これを正とし、`-i` や `-o` オプションを毎回指定しない。
  ```bash
  ssh lb-1
  ssh pg-cluster-1 "journalctl -u patroni -n 50 --no-pager"
  ```
  接続できないホストは `.ssh/gen-keys.sh` の `NODES` に `"ホスト名:IP:ユーザー名"` を追記し、`bash .ssh/gen-keys.sh` を再実行して登録する。ホスト名 ↔ IP の対応もこのファイルを正とする。

## 2. GitOps 原則

このリポジトリの構成はすべて GitOps で管理されている（k8s: Argo CD / NixOS LXC: autoUpgrade / インフラ: Terragrunt）。場当たり的な対応をしないこと。

- **ソース修正が本対応**: 稼働環境への直接変更（`kubectl apply`・`kubectl edit`・ノード上での設定編集など）を恒久対応にしない。必ずリポジトリ上のソースを修正する
- **一時適用は検証目的に限定する**: デバッグのための直接適用（`kubectl apply -k`、rsync + `/tmp/nix` からの一時 rebuild 等）は許容されるが、検証が済んだら必ずソースに反映し、GitOps 経路で本適用する
- **手動変更はいずれ消える**: Argo CD の selfHeal/prune と nixos-upgrade により、ソースに反映されていない変更は自動的に巻き戻される

### 適用経路の早見表

| 資材 | 適用経路 |
| :-- | :-- |
| k8s マニフェスト (`manifests/`, 外部リポジトリの `k8s/`) | master へ push → Argo CD が自動同期 |
| NixOS LXC / VM (`nix/`) | master へ push → `system.autoUpgrade` が自動適用 |
| Terraform (`terraform/`) | ユーザーが `terragrunt apply` を実行（AI は plan まで） |

## 3. Skills 索引

作業種別ごとの手段・コマンド・注意点は `.agents/skills/` を参照する。

| Skill | 用途 |
| :-- | :-- |
| `modify-terraform` | Terraform/Terragrunt 資材の変更 |
| `modify-nix-host` | NixOS ホスト資材の変更・適用・デバッグ |
| `modify-k8s-manifests` | k8s マニフェストの変更・Argo CD 運用 |
| `troubleshoot-k8s-app` | クラスタ上のアプリの障害調査 |
| `sops-secrets` | SOPS シークレットの配線と確認 |
| `deploy-lxc-middleware` | 新規 NixOS LXC ミドルウェアクラスタの構築（フロー型） |

## 4. その他制約

- **Git操作の禁止**:
  特別な指示がない限り、コミットやプッシュ、ブランチ作成などのGit操作（`git` コマンド）は実行しないこと。

- **SOPS操作の禁止**:
  特別な指示がない限り、SOPS を用いたシークレットファイルの作成・編集・復号は実行しないこと。ユーザーにファイルの作成や編集を促すこと。

- **Terraform, Terragrunt操作の禁止**:
  特別な指示がない限り、Terraform, Terragrunt の操作は実行しないこと。ユーザーに操作を促すこと。

- **言い切り調の使用**:
  コメントアウトやドキュメントを記述する際は、です・ます調（敬体）を避け、である・する調（常体）の言い切りを使用すること。
