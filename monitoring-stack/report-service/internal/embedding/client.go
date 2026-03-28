package embedding

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

// Client calls an OpenAI-compatible /v1/embeddings endpoint (e.g. Ollama).
type Client struct {
	baseURL    string
	model      string
	httpClient *http.Client
}

// NewClient reads EMBEDDING_URL and EMBEDDING_MODEL from the environment.
// Defaults to Ollama at http://ollama:11434/v1 with nomic-embed-text (768-dim).
func NewClient() *Client {
	baseURL := os.Getenv("EMBEDDING_URL")
	if baseURL == "" {
		baseURL = "http://ollama:11434/v1"
	}
	model := os.Getenv("EMBEDDING_MODEL")
	if model == "" {
		model = "nomic-embed-text"
	}
	return &Client{
		baseURL:    baseURL,
		model:      model,
		httpClient: &http.Client{},
	}
}

type embeddingRequest struct {
	Input string `json:"input"`
	Model string `json:"model"`
}

type embeddingResponse struct {
	Data []struct {
		Embedding []float32 `json:"embedding"`
	} `json:"data"`
}

// GenerateEmbedding calls the OpenAI-compatible /v1/embeddings endpoint and returns the vector.
func (c *Client) GenerateEmbedding(ctx context.Context, text string) ([]float32, error) {
	if text == "" {
		return nil, nil
	}

	body, err := json.Marshal(embeddingRequest{Input: text, Model: c.model})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/embeddings", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("embedding request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("embedding API returned status %d", resp.StatusCode)
	}

	var result embeddingResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode embedding response: %w", err)
	}

	if len(result.Data) == 0 || len(result.Data[0].Embedding) == 0 {
		return nil, fmt.Errorf("empty embedding response")
	}

	return result.Data[0].Embedding, nil
}
