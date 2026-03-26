
## api-gatewayからのログイン確認

```bash
kubectl port-forward svc/api-gateway-service 5051:80
curl -X POST \
     -H "Content-Type: application/json" \
     -d '{
           "query": "mutation Login($username: String!, $password: String!) { login(username: $username, password: $password) { token expiresIn } }",
           "variables": {
             "username": "admin",
             "password": "admin"
           },
           "operationName": "Login"
         }' \
     http://localhost:5051/graphql
```

## user-serviceからのログイン確認

```bash
kubectl port-forward svc/user-service 5051:80
grpcurl \
  -plaintext \
  -proto user-service/proto/user_service.proto \
  -d '{
    "username": "admin",
    "password": "admin"
  }' \
  localhost:5051 \
  user_service.UserService/Login
```

## ai-service

```bash
grpcurl \
  -plaintext \
  -proto ai-service/proto/ai_service.proto \
  -d '{
    "user_id": "",
    "instructions": "ノード、ポッドの一覧とその状態、リソース使用率（CPU、メモリ、ディスク）、ネットワークの状態、イベントログなどを含むkubernetesクラスターの現在の状態に関する詳細なレポートを生成してください。",
    "data": "",
    "context": ""
  }' \
  localhost:5053 \
  ai_service.AIService/GenerateReport
```

## report-service

```bash
grpcurl \
  -plaintext \
  -proto proto/report_service.proto \
  -d '{
    "report_id": "rep-20251030-001",
    "report_body": "昨夜、KubernetesクラスタでetcdのディスクI/O遅延を示すアラートが複数発生しました。インシデントは30分で解消しましたが、根本原因調査が必要です。",
    "user_id": "user-alice-sa"
  }' \
  localhost:5052 \
  report_service.ReportService/CreateReport
```
