package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/rest"
)

const (
	listenAddr = ":5054"
	namespace  = "default"
)

var (
	dynamicClient        dynamic.Interface
	gvr                  = schema.GroupVersionResource{Group: "argoproj.io", Version: "v1alpha1", Resource: "workflows"}
	aiServiceAddress     = getEnv("AI_SERVICE_ADDRESS", "ai-service:80")
	reportServiceAddress = getEnv("REPORT_SERVICE_ADDRESS", "report-service:80")
	defaultInstructions  = getEnv("DEFAULT_INSTRUCTIONS", "mcp-grafana, mcp-k8sを使用してKubernetesクラスターの状態（ノード、Pod、リソース使用率、イベント）を調査し、日本語でレポートを生成してください。")
)

func getEnv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	cfg, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("failed to get in-cluster config: %v", err)
	}
	dynamicClient, err = dynamic.NewForConfig(cfg)
	if err != nil {
		log.Fatalf("failed to create dynamic client: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("POST /trigger", handleTrigger)
	mux.HandleFunc("POST /webhook", handleWebhook)

	log.Printf("trigger-service listening on %s", listenAddr)
	if err := http.ListenAndServe(listenAddr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	fmt.Fprint(w, "ok")
}

// TriggerRequest is the payload for POST /trigger.
type TriggerRequest struct {
	Instructions string `json:"instructions"`
}

// AlertmanagerWebhook matches the Alertmanager webhook payload format.
type AlertmanagerWebhook struct {
	Alerts []struct {
		Labels      map[string]string `json:"labels"`
		Annotations map[string]string `json:"annotations"`
	} `json:"alerts"`
}

func handleTrigger(w http.ResponseWriter, r *http.Request) {
	var req TriggerRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.Instructions == "" {
		req.Instructions = defaultInstructions
	}

	wfName, err := submitArgoWorkflow(r.Context(), req.Instructions)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to submit workflow: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"workflow": wfName, "status": "submitted"})
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	var webhook AlertmanagerWebhook
	instructions := defaultInstructions

	if err := json.NewDecoder(r.Body).Decode(&webhook); err == nil && len(webhook.Alerts) > 0 {
		alert := webhook.Alerts[0]
		alertName := alert.Labels["alertname"]
		if desc, ok := alert.Annotations["description"]; ok {
			instructions = fmt.Sprintf("Alertmanagerアラート「%s」が発火しました。\n%s\nKubernetesクラスターの状態を調査してレポートを生成してください。", alertName, desc)
		} else {
			instructions = fmt.Sprintf("Alertmanagerアラート「%s」が発火しました。Kubernetesクラスターの状態を調査してレポートを生成してください。", alertName)
		}
	}

	wfName, err := submitArgoWorkflow(r.Context(), instructions)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to submit workflow: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"workflow": wfName, "status": "submitted"})
}

func submitArgoWorkflow(ctx context.Context, instructions string) (string, error) {
	wfName := fmt.Sprintf("ai-report-%d", time.Now().UnixNano()/1e6)
	
	workflow := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"apiVersion": "argoproj.io/v1alpha1",
			"kind":       "Workflow",
			"metadata": map[string]interface{}{
				"name": wfName,
				"labels": map[string]interface{}{
					"triggered-by": "trigger-service",
				},
			},
			"spec": map[string]interface{}{
				"workflowTemplateRef": map[string]interface{}{
					"name": "ai-alert-analyzer",
				},
				"arguments": map[string]interface{}{
					"parameters": []interface{}{
						map[string]interface{}{
							"name":  "instructions",
							"value": instructions,
						},
					},
				},
			},
		},
	}

	result, err := dynamicClient.Resource(gvr).Namespace(namespace).Create(ctx, workflow, metav1.CreateOptions{})
	if err != nil {
		return "", fmt.Errorf("failed to create workflow: %w", err)
	}

	log.Printf("Submitted Argo Workflow: %s", result.GetName())
	return result.GetName(), nil
}
