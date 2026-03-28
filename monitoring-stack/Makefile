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

.PHONY: up cluster prefetch-cilium setup-cilium setup-infra deploy down load-images

up: cluster prefetch-cilium setup-cilium setup-infra deploy

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

up: cluster prefetch-cilium setup-cilium setup-infra build load deploy

build:
	@echo "Building ai-service..."
	docker build -t ai-service:latest ./ai-service
	@echo "Building api-gateway-service..."
	docker build -t api-gateway-service:latest ./api-gateway-service
	@echo "Building job-service..."
	docker build --build-arg TARGET=generate_report -t job-generate-report:latest ./job-service
	@echo "Building notification-service..."
	(cd /home/nixos/work/pechka/_deprecated/api/notifications && docker build --build-arg TARGET=server -t notification-service:latest .)
	@echo "Building report-service..."
	docker build --build-arg TARGET=server -t report-service:latest ./report-service
	@echo "Building trigger-service..."
	docker build -t trigger-service:latest ./trigger-service
	@echo "Building ui..."
	docker build -t ui:latest ./ui
	@echo "Building user-service..."
	docker build -t user-service:latest ./user-service

load:
	kind load docker-image ai-service:latest --name $(CLUSTER_NAME)
	kind load docker-image api-gateway-service:latest --name $(CLUSTER_NAME)
	kind load docker-image job-generate-report:latest --name $(CLUSTER_NAME)
	kind load docker-image notification-service:latest --name $(CLUSTER_NAME)
	kind load docker-image report-service:latest --name $(CLUSTER_NAME)
	kind load docker-image trigger-service:latest --name $(CLUSTER_NAME)
	kind load docker-image ui:latest --name $(CLUSTER_NAME)
	kind load docker-image user-service:latest --name $(CLUSTER_NAME)
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

down:
	@echo "Deleting kind cluster..."
	kind delete cluster --name $(CLUSTER_NAME) --kubeconfig $(KUBECONFIG)
	rm -f $(KUBECONFIG)
