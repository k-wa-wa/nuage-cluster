# Migration to `kind` and Manifest Refactoring

Migrate the local development environment from `minikube` to `kind` (Kubernetes in Docker) to improve consistency and integration. This includes setting up `ollama` for local LLM execution, which will be used by the `ai-service`.

## Proposed Changes

### Infrastructure
#### [NEW] [kind-config.yaml](file:///home/nixos/work/nuage-cluster/monitoring-stack/kind-config.yaml)
Configuration for `kind` cluster with extra port mappings for Ingress (80, 443).

#### [NEW] [setup-kind.sh](file:///home/nixos/work/nuage-cluster/monitoring-stack/setup-kind.sh)
A script to:
1. Create the `kind` cluster without default CNI.
2. Install Cilium.
3. Install Argo Workflows.
4. Apply the `manifests/overlays/kind`.

### Ollama Integration
#### [NEW] [ollama.yaml](file:///home/nixos/work/nuage-cluster/monitoring-stack/manifests/base/ollama.yaml)
Deployment and Service for `ollama`. Includes an init container or post-start script to pull a small model (e.g., `llama3.2`).

### AI Service
#### [MODIFY] [__init__.py](file:///home/nixos/work/nuage-cluster/monitoring-stack/ai-service/src/agent/__init__.py)
Make the model name configurable via the `AI_MODEL_NAME` environment variable, defaulting to `gemini-2.5-flash`.

#### [MODIFY] [ai-service.yaml](file:///home/nixos/work/nuage-cluster/monitoring-stack/manifests/base/ai-service.yaml)
Update environment variables to point `OPENAI_BASE_URL` to `http://ollama:11434/v1` and set `AI_MODEL_NAME`.

### Manifest Refactoring
#### [MODIFY] [kustomization.yaml](file:///home/nixos/work/nuage-cluster/monitoring-stack/manifests/base/kustomization.yaml)
Include all services (User, Trigger, AI, Report, Notification, APIGateway) in the base kustomization. Ensure Cilium-specific Ingress/Gateway resources are included.

#### [NEW] [overlays/kind/kustomization.yaml](file:///home/nixos/work/nuage-cluster/monitoring-stack/manifests/overlays/kind/kustomization.yaml)
Overlay for `kind` cluster with:
- `imagePullPolicy: Never` for all components.
- Port-forwarding or NodePort settings if needed.
- ConfigMaps with local-specific values.

## Verification Plan

### Automated Tests
- Run `tests/integration_test.sh` (once created) to verify the flow from Trigger to Report service.

### Manual Verification
1. Run `./setup-kind.sh` and ensure the cluster is healthy.
2. Verify `ollama` is running and the model is pulled:
   ```bash
   kubectl exec -it $(kubectl get pod -l app=ollama -o jsonpath='{.items[0].metadata.name}') -- ollama list
   ```
3. Run a test Job (e.g., `job-service.yaml`) and check `Report Service` for the generated report.
