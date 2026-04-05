# Use rootful Docker socket to allow BPF operations inside kind nodes.
export DOCKER_HOST = unix:///run/docker.sock

CLUSTER_NAME := monitoring-cluster
KUBECONFIG := $(CURDIR)/.kubeconfig
export KUBECONFIG

KUBECTL := kubectl
HELM := helm

CILIUM_VERSION = v1.16.2
CILIUM_HELM_VERSION = 1.16.2
CILIUM_ENVOY_TAG = v1.29.9-1726784081-a90146d13b4cd7d168d573396ccf2b3db5a3b047

.PHONY: up cluster prefetch-cilium setup-cilium setup-infra deploy down \
        build load load-images rebuild \
        status logs pf-grafana pf-trigger pf-ollama pf-report \
        test-alert es-setup pull-models

# ============================================================
# フルセットアップ
# ============================================================
up: cluster prefetch-cilium setup-cilium setup-infra build load deploy

# ============================================================
# クラスタ管理
# ============================================================
cluster:
	@if ! kind get clusters | grep -q $(CLUSTER_NAME); then \
		kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml --kubeconfig $(KUBECONFIG); \
	fi
	@echo "Setup complete. Use 'export KUBECONFIG=$(KUBECONFIG)' to work here."

prefetch-cilium:
	@echo "Pulling Cilium images on host..."
	docker pull quay.io/cilium/cilium:$(CILIUM_VERSION)
	docker pull quay.io/cilium/operator-generic:$(CILIUM_VERSION)
	docker pull quay.io/cilium/cilium-envoy:$(CILIUM_ENVOY_TAG)
	@echo "Loading Cilium images into kind node..."
	docker save quay.io/cilium/cilium:$(CILIUM_VERSION) \
		| docker exec -i $(CLUSTER_NAME)-control-plane ctr --namespace=k8s.io images import -
	docker save quay.io/cilium/operator-generic:$(CILIUM_VERSION) \
		| docker exec -i $(CLUSTER_NAME)-control-plane ctr --namespace=k8s.io images import -
	docker save quay.io/cilium/cilium-envoy:$(CILIUM_ENVOY_TAG) \
		| docker exec -i $(CLUSTER_NAME)-control-plane ctr --namespace=k8s.io images import -

setup-cilium:
	@echo "Installing Gateway API CRDs..."
	$(KUBECTL) apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/experimental-install.yaml
	@echo "Installing Cilium via Helm..."
	$(HELM) repo add cilium https://helm.cilium.io/ 2>/dev/null || true
	$(HELM) repo update
	$(HELM) upgrade --install cilium cilium/cilium --namespace kube-system \
		--version $(CILIUM_HELM_VERSION) \
		--set image.useDigest=false \
		--set operator.image.useDigest=false \
		--set gatewayAPI.enabled=true \
		--set gatewayAPI.gatewayClass.enabled=true \
		--set kubeProxyReplacement=false \
		--set nodePort.enabled=true \
		--set ingressController.enabled=true \
		--set ingressController.loadbalancerMode=shared \
		--set ingressController.service.type=NodePort \
		--set ingressController.service.insecureNodePort=30000 \
		--set operator.replicas=1
	@echo "Waiting for Cilium pods..."
	@count=0; until $(KUBECTL) get pods -l app.kubernetes.io/name=cilium-agent -n kube-system -o name 2>/dev/null | grep -q "pod/"; do \
		count=$$((count+1)); \
		if [ $$count -ge 90 ]; then echo "ERROR: Timeout (180s) - Cilium pods did not appear."; exit 1; fi; \
		sleep 2; \
	done
	$(KUBECTL) wait --for=condition=ready pod -l app.kubernetes.io/name=cilium-agent -n kube-system --timeout=300s

setup-infra:
	@echo "Installing Argo Workflows..."
	$(KUBECTL) create namespace argo || true
	$(KUBECTL) apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.8/install.yaml
	@echo "Installing Redis..."
	$(HELM) repo add bitnami https://charts.bitnami.com/bitnami && $(HELM) repo update
	$(HELM) upgrade --install redis bitnami/redis --set auth.enabled=false -n default

down:
	@echo "Deleting kind cluster..."
	kind delete cluster --name $(CLUSTER_NAME) --kubeconfig $(KUBECONFIG)
	rm -f $(KUBECONFIG)

# ============================================================
# ビルド・デプロイ
# ============================================================
build:
	@echo "Building ai-service..."
	docker build -t ai-service:latest ./ai-service
	@echo "Building job-service..."
	docker build --build-arg TARGET=generate_report -t job-generate-report:latest ./job-service
	@echo "Building report-service..."
	docker build --build-arg TARGET=server -t report-service:latest ./report-service
	@echo "Building trigger-service..."
	docker build -t trigger-service:latest ./trigger-service

load:
	kind load docker-image ai-service:latest --name $(CLUSTER_NAME)
	kind load docker-image job-generate-report:latest --name $(CLUSTER_NAME)
	kind load docker-image report-service:latest --name $(CLUSTER_NAME)
	kind load docker-image trigger-service:latest --name $(CLUSTER_NAME)
	@echo "Loading ollama into kind..."; \
	docker pull ollama/ollama:latest && kind load docker-image ollama/ollama:latest --name $(CLUSTER_NAME)

deploy:
	@echo "Applying manifests (step 1)..."
	kustomize build --enable-helm manifests/overlays/kind | $(KUBECTL) apply --server-side -f - --force-conflicts || true
	@echo "Waiting for CRDs and resources to stabilize..."
	sleep 15
	@echo "Applying manifests (step 2)..."
	kustomize build --enable-helm manifests/overlays/kind | $(KUBECTL) apply --server-side -f - --force-conflicts

load-images: load

# 単一サービス再ビルド・再デプロイ
# 使い方: make rebuild SERVICE=ai-service
rebuild:
	@if [ -z "$(SERVICE)" ]; then echo "Usage: make rebuild SERVICE=<ai-service|report-service|trigger-service|job-service>"; exit 1; fi
	@echo "Rebuilding $(SERVICE)..."
	@case "$(SERVICE)" in \
		ai-service) \
			docker build -t ai-service:latest ./ai-service && \
			kind load docker-image ai-service:latest --name $(CLUSTER_NAME) && \
			$(KUBECTL) rollout restart deployment/ai-service ;; \
		report-service) \
			docker build --build-arg TARGET=server -t report-service:latest ./report-service && \
			kind load docker-image report-service:latest --name $(CLUSTER_NAME) && \
			$(KUBECTL) rollout restart deployment/report-service ;; \
		trigger-service) \
			docker build -t trigger-service:latest ./trigger-service && \
			kind load docker-image trigger-service:latest --name $(CLUSTER_NAME) && \
			$(KUBECTL) rollout restart deployment/trigger-service ;; \
		job-service) \
			docker build --build-arg TARGET=generate_report -t job-generate-report:latest ./job-service && \
			kind load docker-image job-generate-report:latest --name $(CLUSTER_NAME) ;; \
		*) echo "Unknown service: $(SERVICE)"; exit 1 ;; \
	esac
	@echo "Done: $(SERVICE) redeployed."

# ============================================================
# 状態確認・ログ
# ============================================================

# 全Pod状態表示
status:
	@echo "=== Pods (default namespace) ==="
	$(KUBECTL) get pods -o wide
	@echo ""
	@echo "=== Pods (argo namespace) ==="
	$(KUBECTL) get pods -n argo -o wide
	@echo ""
	@echo "=== Recent Workflows ==="
	$(KUBECTL) get wf --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5 || echo "(no workflows)"

# ログ表示 (使い方: make logs SERVICE=ai-service)
logs:
	@if [ -z "$(SERVICE)" ]; then echo "Usage: make logs SERVICE=<service-name>"; exit 1; fi
	$(KUBECTL) logs -f deployment/$(SERVICE) --tail=100

# ============================================================
# ポートフォワード
# ============================================================
pf-grafana:
	@echo "Grafana → http://localhost:3000  (admin / prom-operator)"
	$(KUBECTL) port-forward svc/kube-prometheus-stack-grafana 3000:80

pf-trigger:
	@echo "trigger-service → http://localhost:5054"
	$(KUBECTL) port-forward svc/trigger-service 5054:80

pf-ollama:
	@echo "Ollama API → http://localhost:11434"
	$(KUBECTL) port-forward svc/ollama 11434:11434

pf-report:
	@echo "report-service HTTP API → http://localhost:5052"
	$(KUBECTL) port-forward svc/report-service 5052:5052

# ============================================================
# テスト・セットアップ
# ============================================================

# サンプルAlertmanagerウェブフック送信 (事前に make pf-trigger 必須)
test-alert:
	@echo "Sending test alert webhook to http://localhost:5054/webhook ..."
	curl -s -X POST http://localhost:5054/webhook \
		-H "Content-Type: application/json" \
		-d '{ \
			"version": "4", \
			"groupKey": "test-group", \
			"status": "firing", \
			"receiver": "ai-analyzer", \
			"alerts": [{ \
				"status": "firing", \
				"labels": { \
					"alertname": "TestAlert", \
					"severity": "warning", \
					"namespace": "default", \
					"pod": "test-pod-xyz" \
				}, \
				"annotations": { \
					"summary": "Test pod is not running", \
					"description": "Pod test-pod-xyz in namespace default has been in CrashLoopBackOff for 5 minutes" \
				} \
			}] \
		}' | python3 -m json.tool || true
	@echo ""
	@echo "Check workflow: kubectl get wf"

# Elasticsearchインデックス作成 (事前に kubectl port-forward svc/elasticsearch-master 9200:9200 必須)
# または make pf-es して実行
es-setup:
	@echo "Creating Elasticsearch index 'reports_index'..."
	@echo "Make sure ES is accessible. Run: kubectl port-forward svc/elasticsearch-master 9200:9200"
	curl -X PUT "http://localhost:9200/reports_index" \
		-H "Content-Type: application/json" \
		-d '{ \
			"mappings": { \
				"properties": { \
					"report_id": {"type": "keyword"}, \
					"report_title": {"type": "text"}, \
					"report_text": {"type": "text"}, \
					"report_type": {"type": "keyword"}, \
					"status": {"type": "keyword"}, \
					"severity": {"type": "keyword"}, \
					"created_at": {"type": "long"}, \
					"report_vector": { \
						"type": "dense_vector", \
						"dims": 768, \
						"index": true, \
						"similarity": "cosine" \
					} \
				} \
			} \
		}'
	@echo ""
	@echo "Index created."

# Ollamaモデルpull (事前に make pf-ollama 必須)
pull-models:
	@echo "Pulling gemma4:12b via Ollama API (requires: make pf-ollama in another terminal)..."
	@echo "This may take a long time depending on network speed."
	curl -X POST http://localhost:11434/api/pull \
		-H "Content-Type: application/json" \
		-d '{"name": "gemma4"}' \
		--no-buffer | while IFS= read -r line; do \
			echo "$$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''), d.get('completed',''), '/', d.get('total',''))" 2>/dev/null || echo "$$line"; \
		done
	@echo "Pulling nomic-embed-text..."
	curl -X POST http://localhost:11434/api/pull \
		-H "Content-Type: application/json" \
		-d '{"name": "nomic-embed-text"}' \
		--no-buffer | while IFS= read -r line; do \
			echo "$$line" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''), d.get('completed',''), '/', d.get('total',''))" 2>/dev/null || echo "$$line"; \
		done
	@echo "Models ready."
