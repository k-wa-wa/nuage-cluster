# Migration to Kind Cluster with Cilium

We have successfully migrated the local development environment from a generic Kubernetes setup to a robust `kind` (Kubernetes in Docker) cluster using **Cilium** for networking and security. This setup follows the patterns established in modern cloud-native development.

## Highlights
- **Architecture Pivot:** Switched from Istio to Cilium for a more lightweight and integrated networking layer.
- **Rootful Docker:** Configured the `Makefile` to use the rootful Docker socket (`/run/docker.sock`) to support Cilium's BPF operations.
- **Cilium Ingress:** Implemented Cilium Ingress for routing traffic to microservices on port `3080`.
- **Ollama Integration:** Added a local LLM service (`ollama`) with the `llama3.2:3b` model pre-loaded for AI-driven features.
- **Modular Manifests:** Refactored Kubernetes manifests using Kustomize and Helm integration for a declarative setup.

## Infrastructure Details
- **Cluster Name:** `monitoring-cluster`
- **Context:** `kind-monitoring-cluster`
- **Port Mapping:** `3080 (Host) -> 30000 (NodePort)`
- **Components:**
  - Cilium 1.16.2 (with Gateway API)
  - Argo Workflows
  - Redis (Bitnami)
  - Prometheus & Loki (Kube-Prometheus-Stack)
  - PostgreSQL 15 (user-service DB)
  - Elasticsearch 8.12.2 (report-service vector store)

## Verification Results

### Pod Health
All core microservices are **Running** in the `kind-monitoring-cluster`:

| Service | Status | Notes |
|---|---|---|
| ai-service | Running | mcp-clients-config ConfigMap fixed |
| api-gateway-service | Running | bind 0.0.0.0:4000 fixed, gRPC connected to user/report |
| elasticsearch | Running | single-node, no auth, analysis-kuromoji plugin |
| notification-service | Running | |
| ollama | Running | llama3.2:3b loaded |
| postgres | Running | userdb created, schema initialized |
| report-service | Running | ES_URL + GEMINI_API_KEY injected |
| user-service | Running | DB env vars injected |
| trigger-service | ErrImageNeverPull | source missing: pechka/_deprecated/api/trigger not found |

### Cilium Ingress Connectivity
The system is reachable from the host via Cilium Ingress on port `3080`:
```bash
# GraphQL API (HTTP 200)
curl -X POST http://127.0.0.1:3080/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __typename }"}'
# → {"data":{"__typename":"Query"}}

# user-service is gRPC-only; test via grpcurl, not curl
# Internal gRPC connectivity confirmed via api-gateway logs:
# "Connected to User Service at http://user-service:80"
# "Connected to Report Service at http://report-service:80"
```

> [!NOTE]
> `curl 127.0.0.1:3080/user` returns 502 — this is expected. user-service is a gRPC service
> and cannot be proxied via HTTP/1.1. User operations are accessed through `/graphql` (api-gateway).

> [!NOTE]
> `trigger-service` remains in `ErrImageNeverPull` as its source code is not present at
> `pechka/_deprecated/api/trigger`. The directory only contains `notifications` and `prototype`.

### Ollama Readiness
The `ollama` pod is operational and the `llama3.2:3b` model has been successfully pre-loaded.

## Fixes Applied (2026-03-26)
1. **api-gateway bug**: Changed bind from `127.0.0.1:8000` → `0.0.0.0:4000`, rebuilt image.
2. **Ingress**: Changed `io.cilium/ingress.class` annotation → `spec.ingressClassName: cilium`.
3. **user-service env**: Added `DB_HOST=postgres`, `DB_NAME=userdb`, `DB_USER/PASSWORD/PORT`.
4. **report-service env**: Added `ES_URL=http://elasticsearch:9200`, `GEMINI_API_KEY` from secret.
5. **report-service port**: Fixed manifest containerPort `5052`→`5051` to match Go code.
6. **api-gateway env**: Added `USER_SERVICE_URL=http://user-service:80`, `REPORT_SERVICE_URL=http://report-service:80`.
7. **PostgreSQL**: New `manifests/base/postgres.yaml` — Deployment + init SQL ConfigMap + Service `postgres-postgresql`.
8. **Elasticsearch**: New `manifests/base/elasticsearch.yaml` — Deployment + Service `elasticsearch-master` (matches ExternalName target).
9. **ai-service**: Uncommented `mcp/config.yaml` in kustomization to resolve ConfigMap mount failure.
10. **trigger-service**: Commented out from kustomization (source not available).

## Access
- **GraphQL API:** `http://127.0.0.1:3080/graphql`
- **Context Switch:** `kubectl config use-context kind-monitoring-cluster`
- **GEMINI_API_KEY:** Set real key in `manifests/overlays/kind/kustomization.yaml` secretGenerator.

---
*Verified on Thu Mar 26 2026*
