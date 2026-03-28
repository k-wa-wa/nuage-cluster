package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

const (
	listenAddr = ":5054"
	namespace  = "default"
)

var (
	k8sClient            *kubernetes.Clientset
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
	k8sClient, err = kubernetes.NewForConfig(cfg)
	if err != nil {
		log.Fatalf("failed to create k8s client: %v", err)
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
	UserID       string `json:"user_id"`
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

	jobName, err := createReportJob(r.Context(), req.Instructions)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to create job: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"job": jobName, "status": "submitted"})
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

	jobName, err := createReportJob(r.Context(), instructions)
	if err != nil {
		http.Error(w, fmt.Sprintf("failed to create job: %v", err), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"job": jobName, "status": "submitted"})
}

func createReportJob(ctx context.Context, instructions string) (string, error) {
	jobName := fmt.Sprintf("report-job-%d", time.Now().UnixNano())
	ttl := int32(3600)
	backoffLimit := int32(0)
	pullNever := corev1.PullNever

	job := &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      jobName,
			Namespace: namespace,
			Labels:    map[string]string{"app": "report-job", "triggered-by": "trigger-service"},
		},
		Spec: batchv1.JobSpec{
			BackoffLimit:            &backoffLimit,
			TTLSecondsAfterFinished: &ttl,
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{"app": "report-job"},
				},
				Spec: corev1.PodSpec{
					RestartPolicy: corev1.RestartPolicyNever,
					Containers: []corev1.Container{
						{
							Name:            "generate-report",
							Image:           "job-generate-report:latest",
							ImagePullPolicy: pullNever,
							Env: []corev1.EnvVar{
								{Name: "AI_SERVICE_ADDRESS", Value: aiServiceAddress},
								{Name: "REPORT_SERVICE_ADDRESS", Value: reportServiceAddress},
								{Name: "INSTRUCTIONS", Value: instructions},
							},
						},
					},
				},
			},
		},
	}

	created, err := k8sClient.BatchV1().Jobs(namespace).Create(ctx, job, metav1.CreateOptions{})
	if err != nil {
		return "", fmt.Errorf("create k8s job: %w", err)
	}

	log.Printf("created job %s", created.Name)
	return created.Name, nil
}
