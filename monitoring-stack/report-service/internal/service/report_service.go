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
// Grafana Infinity datasource (変数クエリ含む) から参照される
func (s *ReportService) HandleListReports(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	docs, _, err := s.esClient.SearchReports(ctx, 100, "")
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	// Grafana Infinity UQL で扱いやすいフラット構造に整形
	type ReportSummary struct {
		ReportID    string `json:"report_id"`
		ReportTitle string `json:"report_title"`
		Severity    string `json:"severity"`
		Status      string `json:"status"`
		CreatedAt   int64  `json:"created_at"`
		// 本文プレビュー (先頭200文字)
		Preview string `json:"preview"`
	}

	summaries := make([]ReportSummary, 0, len(docs))
	for _, doc := range docs {
		preview := doc.ReportText
		if len([]rune(preview)) > 200 {
			runes := []rune(preview)
			preview = string(runes[:200]) + "..."
		}
		summaries = append(summaries, ReportSummary{
			ReportID:    doc.ReportID,
			ReportTitle: doc.ReportTitle,
			Severity:    doc.Severity,
			Status:      doc.Status,
			CreatedAt:   doc.CreatedAt,
			Preview:     preview,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(summaries)
}

// HandleGetReportDetails は詳細と類似レポート取得のための HTTP ハンドラ
// Grafana Infinity + Business Text パネルから直接使えるようフラットなフィールドも返す
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

	// Grafana Business Text パネルで直接使えるようフラットフィールドも含める
	type SimilarIssue struct {
		ReportID    string `json:"report_id"`
		ReportTitle string `json:"report_title"`
		Severity    string `json:"severity"`
		CreatedAt   int64  `json:"created_at"`
	}
	var similarIssues []SimilarIssue
	for _, s := range similar {
		if s.ReportID != doc.ReportID {
			similarIssues = append(similarIssues, SimilarIssue{
				ReportID:    s.ReportID,
				ReportTitle: s.ReportTitle,
				Severity:    s.Severity,
				CreatedAt:   s.CreatedAt,
			})
		}
	}

	response := map[string]interface{}{
		// フラットフィールド (Grafana Infinity + Business Text 用)
		"report_id":      doc.ReportID,
		"report_title":   doc.ReportTitle,
		"report_text":    doc.ReportText,
		"severity":       doc.Severity,
		"status":         doc.Status,
		"created_at":     doc.CreatedAt,
		"similar_issues": similarIssues,
		// ネストされた元データ (後方互換性)
		"report": doc,
	}

	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(response)
}

