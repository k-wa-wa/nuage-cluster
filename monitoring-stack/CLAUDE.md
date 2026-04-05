# Monitoring Stack - Claude Code Guide

AIによるKubernetes障害調査・レポート自動生成システム。
AlertmanagerのWebhookを受け取り、Argo WorkflowでAIエージェントが調査→Markdownレポート生成→Elasticsearchに保存→Grafanaで可視化する。

## アーキテクチャ概要

```
Alertmanager
    ↓ POST /webhook
trigger-service (Go, port 5054)
    ↓ Argo WorkflowCRD作成 (非同期, 202即返し)
Argo Workflow
    ↓ job-service コンテナ起動
job-service (Go)
    ↓ gRPC streaming
ai-service (Python gRPC, port 5053)
    ├── MCPツール呼び出し (mcp-k8s, mcp-grafana)
    └── Ollama (gemma4:12b) でレポート生成
    ↓ gRPC
report-service (Go, gRPC:5051, HTTP:5052)
    ├── Elasticsearch にベクトル付きで保存
    └── HTTP API → Grafana (Infinity + Business Text)
```

## サービス一覧とポート

| サービス | 言語 | ポート | 役割 |
|---------|------|--------|------|
| trigger-service | Go | 5054 | Alertmanagerウェブフック受信 |
| ai-service | Python | 5053 (gRPC) | AIエージェント本体 |
| report-service | Go | 5051 (gRPC), 5052 (HTTP) | レポート永続化・API |
| job-service | Go | - | Argoタスク実行 |
| ollama | - | 11434 | LLM推論 (gemma4 [=e4b, 9.6GB] + nomic-embed-text) |
| elasticsearch | - | 9200 | ベクトルDB |
| mcp-k8s | - | 3001 | K8s状態取得MCPサーバー |
| mcp-grafana | - | 8000 | GrafanaクエリMCPサーバー |
| Grafana | - | 80 (svc), 30000 (NodePort) | 可視化 |

## ローカル開発 (kind)

### 前提条件
- Docker (rootful socket: `/run/docker.sock`)
- kind, kubectl, helm, kustomize
- Kubernetesシークレット `genai-credentials` (OPENAI_API_KEY, OPENAI_BASE_URL)

### クラスタ起動
```bash
# 初回フルセットアップ (時間がかかる)
make up

# 各ステップ単独
make cluster          # kindクラスタ作成
make prefetch-cilium  # Ciliumイメージpre-load
make setup-cilium     # Ciliumインストール
make setup-infra      # Argo Workflows + Redis
make build            # Dockerイメージビルド
make load             # kindへイメージロード
make deploy           # kustomize apply
make pull-models      # Ollamaモデルpull (要:deploy後)
make es-setup         # Elasticsearchインデックス作成
```

### kubeconfig
```bash
export KUBECONFIG=$(pwd)/.kubeconfig
```

### アクセス先 (ポートフォワード)
```bash
make pf-grafana     # Grafana → http://localhost:3000
make pf-trigger     # trigger-service → http://localhost:5054
make pf-ollama      # Ollama → http://localhost:11434
make pf-report      # report-service HTTP → http://localhost:5052
```

### ログ確認
```bash
make logs SERVICE=ai-service
make logs SERVICE=report-service
make logs SERVICE=trigger-service
make logs SERVICE=ollama
```

### 単一サービス再ビルド・再デプロイ
```bash
make rebuild SERVICE=ai-service
make rebuild SERVICE=report-service
make rebuild SERVICE=trigger-service
make rebuild SERVICE=job-service
```

### テスト送信
```bash
make test-alert     # サンプルAlertmanagerウェブフック送信 (pf-trigger必須)
make es-setup       # ESインデックス再作成
```

### 状態確認
```bash
make status         # 全Pod状態表示
```

## シークレット設定

```bash
# genai-credentials Secret作成 (Ollamaをクラスタ内で使う場合)
kubectl create secret generic genai-credentials \
  --from-literal=OPENAI_API_KEY=dummy \
  --from-literal=OPENAI_BASE_URL=http://ollama:11434/v1
```

## 主要ファイル

| ファイル | 説明 |
|---------|------|
| `ai-service/src/agent/__init__.py` | AIエージェント本体。システムプロンプト・ループ・ツール呼び出し |
| `ai-service/src/server.py` | gRPCサーバー |
| `report-service/internal/service/report_service.go` | レポートCRUD・HTTP API |
| `report-service/internal/elasticsearch/es_client.go` | ESクライアント |
| `trigger-service/main.go` | Webhookレシーバー → Argo Workflow作成 |
| `job-service/cmd/generate_report/main.go` | AI呼び出し→保存オーケストレーション |
| `manifests/base/ai-service.yaml` | AIサービスDeployment (モデル名はここで設定) |
| `manifests/base/ollama.yaml` | Ollama Deployment |
| `manifests/base/grafana-dashboard.yaml` | Grafanaダッシュボード定義 |
| `manifests/base/helm/prometheus-stack-custom.yaml` | Grafana設定・プラグイン |
| `manifests/base/workflow-template.yaml` | Argo WorkflowTemplate |
| `manifests/base/mcp/config.yaml` | MCPクライアント設定 |
| `report-service/db/create_index.sh` | ESインデックス作成コマンド |

## protoファイルの更新

proto変更時は各サービスで再生成が必要:

```bash
# ai-service (Python)
cd ai-service
python -m grpc_tools.protoc -I proto --python_out=src/pb --grpc_python_out=src/pb proto/ai_service.proto

# report-service (Go)
cd report-service
protoc --go_out=internal/pb --go_opt=paths=source_relative \
  --go-grpc_out=internal/pb --go-grpc_opt=paths=source_relative \
  proto/report_service.proto

# job-service (Go) - ai_serviceとreport_serviceの両方
cd job-service
# ai_service proto
protoc --go_out=internal/pb/ai_service --go_opt=paths=source_relative \
  --go-grpc_out=internal/pb/ai_service --go-grpc_opt=paths=source_relative \
  proto/ai_service.proto
```

## Grafanaダッシュボード設計

### AI Summary Dashboard
- **変数 `report_id`**: レポートIDドロップダウン (Infinityクエリ)
- **Panel 1 - Reports List**: 直近レポートのテーブル一覧 (Infinity datasource)
- **Panel 2 - Report Detail**: 選択レポートの詳細表示 (Business Text + Markdown + Mermaid)

### Grafana アクセス
- ローカル: `make pf-grafana` → http://localhost:3000
- kind NodePort経由: http://localhost:3080/grafana (Cilium Ingress)
- デフォルト認証: admin / prom-operator

## AIレポート形式

AIは以下の構造のMarkdownレポートを生成する:
- 重大度・ステータス・発生時刻のバッジ
- 概要
- タイムライン (テーブル)
- 根本原因分析
- 影響サービス一覧
- インシデントフロー (Mermaidダイアグラム)
- 解決手順 (番号付きリスト)
- 参考情報

## トラブルシューティング

### Ollamaモデルが起動しない
```bash
# モデルpullジョブを手動実行
kubectl delete job ollama-pull-models --ignore-not-found
kubectl apply -f manifests/base/ollama-pull-job.yaml
kubectl logs -f job/ollama-pull-models
```

### ESインデックスエラー
```bash
# インデックス再作成
make es-setup
# または
kubectl exec -it deploy/elasticsearch-master -- bash -c "$(cat report-service/db/create_index.sh)"
```

### Argo Workflowが起動しない
```bash
kubectl get wf -n default
kubectl describe wf <workflow-name> -n default
```

### AIサービスのMCPツールエラー
```bash
make logs SERVICE=ai-service
# mcp-k8sとmcp-grafanaのPodが起動しているか確認
kubectl get pods -l app=mcp-k8s
kubectl get pods -l app=mcp-grafana
```
