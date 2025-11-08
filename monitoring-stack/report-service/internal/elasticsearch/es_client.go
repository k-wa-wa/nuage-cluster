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

// GetReportByID は指定されたレポートIDのドキュメントを Elasticsearch から取得
func (c *Client) GetReportByID(ctx context.Context, reportID string) (*ReportDocument, error) {
	url := fmt.Sprintf("%s/%s/_doc/%s", c.esURL, indexName, reportID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	if c.username != "" && c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to send request to ES: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil // レポートが見つからない場合は nil を返す
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("ES returned error status: %s", resp.Status)
	}

	var esResponse struct {
		Source ReportDocument `json:"_source"`
		Found  bool           `json:"found"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&esResponse); err != nil {
		return nil, fmt.Errorf("failed to decode ES response: %w", err)
	}

	if !esResponse.Found {
		return nil, nil
	}

	return &esResponse.Source, nil
}

// SearchReports はレポートを検索し、ページネーションを適用
func (c *Client) SearchReports(ctx context.Context, userID string, pageSize int, pageToken string) ([]ReportDocument, int, error) {
	if pageSize <= 0 {
		pageSize = 10 // デフォルトのページサイズ
	}

	query := map[string]interface{}{
		"sort": []map[string]interface{}{
			{"created_at": "desc"}, // 最新のレポートから取得
		},
		"size": pageSize,
	}

	if userID != "" {
		query["query"] = map[string]interface{}{
			"term": map[string]interface{}{
				"user_id.keyword": userID,
			},
		}
	}

	// pageToken (今回は report_id を想定) を使ったページネーション
	if pageToken != "" {
		// search_after を使用して、より堅牢なページネーションを実現
		// ただし、search_after にはソートキーの値を指定する必要があるため、
		// 実際の ReportDocument を取得してその created_at を使う必要がある。
		// 今回は簡易的に from + size で実装する。
		// TODO: 実際のプロダクションでは search_after を検討
		query["search_after"] = []interface{}{pageToken} // これは簡易的な実装であり、created_at の値が必要
	}

	queryJSON, err := json.Marshal(query)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to marshal search query: %w", err)
	}

	url := fmt.Sprintf("%s/%s/_search", c.esURL, indexName)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(queryJSON))
	if err != nil {
		return nil, 0, err
	}
	req.Header.Set("Content-Type", "application/json")

	if c.username != "" && c.password != "" {
		req.SetBasicAuth(c.username, c.password)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to send search request to ES: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return nil, 0, fmt.Errorf("ES returned error status: %s", resp.Status)
	}

	var esResponse struct {
		Hits struct {
			Total struct {
				Value int `json:"value"`
			} `json:"total"`
			Hits []struct {
				Source ReportDocument `json:"_source"`
			} `json:"hits"`
		} `json:"hits"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&esResponse); err != nil {
		return nil, 0, fmt.Errorf("failed to decode ES search response: %w", err)
	}

	var reports []ReportDocument
	for _, hit := range esResponse.Hits.Hits {
		reports = append(reports, hit.Source)
	}

	return reports, esResponse.Hits.Total.Value, nil
}
