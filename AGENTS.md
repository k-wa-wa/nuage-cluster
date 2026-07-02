# Nuage Cluster Workspace Rules

このファイルは、`nuage-cluster` リポジトリで動作するAIアシスタント（Agent）向けの動作ルールと前提条件を定義する。アシスタントは、コマンド実行やファイル編集の際、これらのルールを厳格に適用する必要がある。

## 1. コマンド実行時の環境変数とPATHの設定

- **PATHの優先指定**:
  このワークスペースでCLIツール（`kubectl`, `talosctl`, `terragrunt` 等）を実行する際は、事前に以下のパスを `PATH` 環境変数に含める必要がある。
  ```bash
  export PATH=$HOME/.nix-profile/bin:/opt/homebrew/bin:$PATH
  ```
  コマンド実行時に「`command not found`」などのエラーが発生した場合は、この環境変数が適切に設定されているか確認し、設定した上でコマンドを再実行すること。

- **KUBECONFIGの指定**:
  Kubernetes関連のコマンド（`kubectl`, `kustomize`, `helm` など）を実行する際は、デフォルトで以下のパスを `KUBECONFIG` として使用すること。
  ```bash
  export KUBECONFIG=terraform/vpc/zone-private-k8s/kubeconfig
  ```
  もし `kubectl` 実行時に `connection refused`（例: `localhost:8080` への接続失敗）のエラーが発生した場合は、`KUBECONFIG` が環境変数に正しく指定されていない、もしくは空になっている可能性が高いため、必ず設定を確認すること。

## 2. ツールおよび設定ファイルの配置場所

- **Talos Linux の操作 (`talosctl`)**:
  `talosctl` を使用する際は、以下の設定ファイルを `--talosconfig` に指定すること。
  ```bash
  --talosconfig terraform/vpc/zone-private-k8s/talosconfig
  ```
  対象ノードのIP（例: `10.20.1.11`）やロードバランサーの外部IP（`192.168.5.200`）を適切に指定すること。

- **Terragrunt / Terraform**:
  Terraform（およびTerragrunt）によるインフラ操作は、以下のディレクトリ配下で行うこと。
  ```
  terraform/vpc/zone-private-k8s/
  ```

## 3. その他制約

- **Git操作の禁止**:
  特別な指示がない限り、コミットやプッシュ、ブランチ作成などのGit操作（`git` コマンド）は実行しないこと。

- **言い切り調の使用**:
  コメントアウトやドキュメントを記述する際は、です・ます調（敬体）を避け、である・する調（常体）の言い切りを使用すること。
