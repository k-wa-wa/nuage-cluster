package elasticsearch

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

const indexName = "reports_index"

// Client は Elasticsearch と通信するためのラッパー
type Client struct {
	httpClient *http.Client
	esURL      string
	username   string
	password   string
}

// NewClient は ES クライアントを初期化
func NewClient() *Client {
	esURL := os.Getenv("ES_URL")
	username := os.Getenv("ES_USERNAME")
	password := os.Getenv("ES_PASSWORD")

	// 証明書の検証を無効化する設定
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	return &Client{
		httpClient: &http.Client{Transport: tr},
		esURL:      esURL,
		username:   username,
		password:   password,
	}
}

// ReportDocument は ES に格納するドキュメント構造
type ReportDocument struct {
	ReportID     string    `json:"report_id"`
	ReportText   string    `json:"report_text"`
	ReportVector []float32 `json:"report_vector"` // Geminiから取得したベクトル
	UserID       string    `json:"user_id"`
	CreatedAt    int64     `json:"created_at"`
}

// IndexReport はレポートドキュメントを Elasticsearch に挿入
func (c *Client) IndexReport(ctx context.Context, doc ReportDocument) error {
	docJSON, err := json.Marshal(doc)
	fmt.Println(string(docJSON))
	if err != nil {
		return fmt.Errorf("failed to marshal report: %w", err)
	}

	// ES のインデックスAPIを呼び出し
	url := fmt.Sprintf("%s/%s/_doc/%s", c.esURL, indexName, doc.ReportID)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(docJSON))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	if c.username != "" && c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to send request to ES: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return fmt.Errorf("ES returned error status: %s", resp.Status)
	}

	return nil
}
