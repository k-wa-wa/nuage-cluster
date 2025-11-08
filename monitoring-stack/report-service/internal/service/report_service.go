package service

import (
	"context"
	"log"
	"time"

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

	// サーバー側で created_at_unix を設定
	createdAtUnix := time.Now().Unix()

	// 2. ES に格納するドキュメントを作成
	doc := elasticsearch.ReportDocument{
		ReportID:     req.GetReportId(),
		ReportText:   req.GetReportBody(),
		ReportVector: vector, // 768次元のベクトル
		UserID:       req.GetUserId(),
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
			UserId:        req.GetUserId(),
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
			UserId:        doc.UserID,
			CreatedAtUnix: doc.CreatedAt,
		},
		Success: true,
		Message: "Report retrieved successfully",
	}, nil
}

// ListReports はユーザーIDに基づいてレポートのリストを取得
func (s *ReportService) ListReports(ctx context.Context, req *pb.ListReportsRequest) (*pb.ListReportsResponse, error) {
	log.Printf("Received ListReports request for PageSize: %d, PageToken: %s", req.GetPageSize(), req.GetPageToken())

	// ページネーションとフィルタリングのロジックをESクライアントに渡す
	// TODO: page_token の実装は後回し。今回は単純なページングのみ
	docs, total, err := s.esClient.SearchReports(ctx, req.GetUserId(), int(req.GetPageSize()), req.GetPageToken())
	if err != nil {
		log.Printf("Error searching reports in ES: %v", err)
		return &pb.ListReportsResponse{Success: false, Message: "Failed to list reports"}, err
	}

	var reports []*pb.Report
	for _, doc := range docs {
		reports = append(reports, &pb.Report{
			ReportId:      doc.ReportID,
			ReportBody:    doc.ReportText,
			UserId:        doc.UserID,
			CreatedAtUnix: doc.CreatedAt,
		})
	}

	// TODO: next_page_token の生成ロジックを実装
	nextPageToken := ""
	if int(req.GetPageSize()) > 0 && len(docs) == int(req.GetPageSize()) {
		// 簡単な例: 最後のレポートIDをトークンとする
		// 実際には、より堅牢なページネーション戦略が必要 (例: search_after)
		nextPageToken = docs[len(docs)-1].ReportID
	}
	_ = total // total は現時点では使用しないが、将来的に必要になる可能性

	return &pb.ListReportsResponse{
		Reports:       reports,
		NextPageToken: nextPageToken,
		Success:       true,
		Message:       "Reports listed successfully",
	}, nil
}
