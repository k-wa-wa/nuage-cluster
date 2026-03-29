package service

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"report-service/internal/elasticsearch"
	"report-service/internal/embedding"
	"report-service/internal/pb"
)

// ReportService は gRPC サービスの実装構造体
type ReportService struct {
	pb.UnimplementedReportServiceServer // 埋め込み（前方互換性のため）
	esClient                            *elasticsearch.Client
	embeddingClient                     *embedding.Client
}

// NewReportService は ReportService のインスタンスを作成
func NewReportService(ctx context.Context) (*ReportService, error) {
	return &ReportService{
		esClient:        elasticsearch.NewClient(),
		embeddingClient: embedding.NewClient(),
	}, nil
}

// CreateReport はレポート作成のメインロジック
func (s *ReportService) CreateReport(ctx context.Context, req *pb.CreateReportRequest) (*pb.CreateReportResponse, error) {
	log.Printf("Received CreateReport request for ID: %s", req.GetReportId())

	// 1. ベクトル化 (OpenAI互換 embedding API 呼び出し)
	// Embedding が失敗してもレポートの保存自体は継続する
	vector, err := s.embeddingClient.GenerateEmbedding(ctx, req.GetReportBody())
	if err != nil {
		log.Printf("Warning: failed to generate embedding: %v. Continuing without vector.", err)
		vector = nil
	}

	// サーバー側で created_at_unix を設定
	createdAtUnix := time.Now().Unix()

	// 2. ES に格納するドキュメントを作成
	doc := elasticsearch.ReportDocument{
		ReportID:     req.GetReportId(),
		ReportText:   req.GetReportBody(),
		ReportVector: vector,
		ReportTitle:  req.GetReportTitle(),
		ReportType:   req.GetReportType(),
		Status:       req.GetStatus(),
		Severity:     req.GetSeverity().String(), // enumを文字列として保存
		CreatedAt:    createdAtUnix,
	}

	// 3. 永続化 (Elasticsearch への挿入)
	if err := s.esClient.IndexReport(ctx, doc); err != nil {
		log.Printf("Error indexing report to ES: %v", err)
		return &pb.CreateReportResponse{Success: false, Message: "Persistence failed"}, err
	}

	// 成功したら作成されたレポートを返す
	return &pb.CreateReportResponse{
		Report: &pb.Report{
			ReportId:      req.GetReportId(),
			ReportBody:    req.GetReportBody(),
			ReportTitle:   req.GetReportTitle(),
			ReportType:    req.GetReportType(),
			Status:        req.GetStatus(),
			Severity:      req.GetSeverity(),
			CreatedAtUnix: createdAtUnix,
		},
		Success: true,
		Message: "Report created successfully",
	}, nil
}

// GetReport は指定されたレポートIDのレポートを取得
func (s *ReportService) GetReport(ctx context.Context, req *pb.GetReportRequest) (*pb.GetReportResponse, error) {
	log.Printf("Received GetReport request for ID: %s", req.GetReportId())

	doc, err := s.esClient.GetReportByID(ctx, req.GetReportId())
	if err != nil {
		log.Printf("Error getting report from ES: %v", err)
		return &pb.GetReportResponse{Success: false, Message: "Failed to get report"}, err
	}
	if doc == nil {
		return &pb.GetReportResponse{Success: false, Message: "Report not found"}, nil
	}

	return &pb.GetReportResponse{
		Report: &pb.Report{
			ReportId:      doc.ReportID,
			ReportBody:    doc.ReportText,
			ReportTitle:   doc.ReportTitle,
			ReportType:    doc.ReportType,
			Status:        doc.Status,
			Severity:      pb.Severity(pb.Severity_value[doc.Severity]),
			CreatedAtUnix: doc.CreatedAt,
		},
		Success: true,
		Message: "Report retrieved successfully",
	}, nil
}

// ListReports はユーザーIDに基づいてレポートのリストを取得
func (s *ReportService) ListReports(ctx context.Context, req *pb.ListReportsRequest) (*pb.ListReportsResponse, error) {
	log.Printf("Received ListReports request for PageSize: %d, PageToken: %s", req.GetPageSize(), req.GetPageToken())

	docs, total, err := s.esClient.SearchReports(ctx, int(req.GetPageSize()), req.GetPageToken())
	if err != nil {
		log.Printf("Error searching reports in ES: %v", err)
		return &pb.ListReportsResponse{Success: false, Message: "Failed to list reports"}, err
	}

	var reports []*pb.Report
	for _, doc := range docs {
		reports = append(reports, &pb.Report{
			ReportId:      doc.ReportID,
			ReportBody:    doc.ReportText,
			ReportTitle:   doc.ReportTitle,
			ReportType:    doc.ReportType,
			Status:        doc.Status,
			Severity:      pb.Severity(pb.Severity_value[doc.Severity]),
			CreatedAtUnix: doc.CreatedAt,
		})
	}

	nextPageToken := ""
	if int(req.GetPageSize()) > 0 && len(docs) == int(req.GetPageSize()) {
		nextPageToken = docs[len(docs)-1].ReportID
	}
	_ = total

	return &pb.ListReportsResponse{
		Reports:       reports,
		NextPageToken: nextPageToken,
		Success:       true,
		Message:       "Reports listed successfully",
	}, nil
}

// HandleListReports は一覧取得のための HTTP ハンドラ
func (s *ReportService) HandleListReports(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	// 簡易的に全件取得するように、page_size=100を想定
	docs, _, err := s.esClient.SearchReports(ctx, 100, "")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(docs)
}

// HandleGetReportDetails は詳細と類似レポート取得のための HTTP ハンドラ
func (s *ReportService) HandleGetReportDetails(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	// URL末尾の ID を取得 (/api/v1/reports/report-123/details)
	parts := strings.Split(r.URL.Path, "/")
	if len(parts) < 5 {
		http.Error(w, "invalid path", http.StatusBadRequest)
		return
	}
	reportID := parts[4]

	doc, err := s.esClient.GetReportByID(ctx, reportID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if doc == nil {
		http.NotFound(w, r)
		return
	}

	// 類似レポートの検索 (ベクトルを使用)
	similar, err := s.esClient.SearchSimilarReports(ctx, doc.ReportVector, 5)
	if err != nil {
		log.Printf("Warning: failed to fetch similar reports: %v", err)
	}

	response := map[string]interface{}{
		"report":         doc,
		"similar_issues": similar,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

