package geminiclient

import (
	"context"
	"fmt"
	"os"

	"github.com/google/generative-ai-go/genai"
	"google.golang.org/api/option"
)

const embeddingModel = "text-embedding-004" // 768次元

// Client は Gemini API と通信するためのラッパー
type Client struct {
	genaiClient *genai.Client
}

// NewClient は Gemini クライアントを初期化
func NewClient(ctx context.Context) (*Client, error) {
	apiKey := os.Getenv("GEMINI_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GEMINI_API_KEY environment variable not set")
	}

	client, err := genai.NewClient(ctx, option.WithAPIKey(apiKey))
	if err != nil {
		return nil, fmt.Errorf("failed to create gemini client: %w", err)
	}

	return &Client{genaiClient: client}, nil
}

// GenerateEmbedding は指定されたテキストの埋め込みベクトルを生成する
func (c *Client) GenerateEmbedding(ctx context.Context, text string) ([]float32, error) {
	if text == "" {
		return nil, nil
	}

	res, err := c.genaiClient.EmbedContent(ctx, embeddingModel, genai.Text(text))
	if err != nil {
		return nil, fmt.Errorf("failed to embed content: %w", err)
	}

	if len(res.Embedding.Values) == 0 {
		return nil, fmt.Errorf("received empty embedding response")
	}

	return res.Embedding.Values, nil
}
