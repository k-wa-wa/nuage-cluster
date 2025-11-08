package service

import (
	"context"
	"log"

	"report-service/internal/elasticsearch"
	"report-service/internal/gemini"
	"report-service/internal/pb"
)

// ReportService は gRPC サービスの実装構造体
type ReportService struct {
	pb.UnimplementedReportServiceServer // 埋め込み（前方互換性のため）
	esClient                            *elasticsearch.Client
	geminiClient                        *gemini.Client
}

// NewReportService は ReportService のインスタンスを作成
func NewReportService(ctx context.Context) (*ReportService, error) {
	geminiClient, err := gemini.NewClient(ctx)
	if err != nil {
		return nil, err
	}

	return &ReportService{
		esClient:     elasticsearch.NewClient(),
		geminiClient: geminiClient,
	}, nil
}

// CreateReport はレポート作成のメインロジック
func (s *ReportService) CreateReport(ctx context.Context, req *pb.CreateReportRequest) (*pb.CreateReportResponse, error) {
	log.Printf("Received CreateReport request for ID: %s", req.GetReportId())

	// 1. ベクトル化 (Gemini API 呼び出し)
	vector, err := s.geminiClient.GenerateEmbedding(ctx, req.GetReportBody())
	if err != nil {
		log.Printf("Error generating embedding: %v", err)
		return &pb.CreateReportResponse{Success: false, Message: "Embedding failed"}, err
	}

	// 2. ES に格納するドキュメントを作成
	doc := elasticsearch.ReportDocument{
		ReportID:     req.GetReportId(),
		ReportText:   req.GetReportBody(),
		ReportVector: vector, // 768次元のベクトル
		UserID:       req.GetUserId(),
		CreatedAt:    req.GetCreatedAtUnix(),
	}

	// 3. 永続化 (Elasticsearch への挿入)
	if err := s.esClient.IndexReport(ctx, doc); err != nil {
		log.Printf("Error indexing report to ES: %v", err)
		return &pb.CreateReportResponse{Success: false, Message: "Persistence failed"}, err
	}

	return &pb.CreateReportResponse{Success: true, Message: "Report created successfully"}, nil
}
