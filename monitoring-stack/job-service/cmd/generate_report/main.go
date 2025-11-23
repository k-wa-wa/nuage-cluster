package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	aipb "job-service/internal/pb/ai_service"
	reportpb "job-service/internal/pb/report_service"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

var (
	aiServiceAddress     string
	reportServiceAddress string
)

func init() {
	aiServiceAddress = os.Getenv("AI_SERVICE_ADDRESS")
	reportServiceAddress = os.Getenv("REPORT_SERVICE_ADDRESS")
}

// GenerateReportFromInstructions は指定された指示に基づいてレポートを生成し、結果のレポートを返します。
func GenerateReportFromInstructions(instructions string) (*aipb.Report, error) {
	// gRPCサーバーへの接続を確立
	conn, err := grpc.NewClient(aiServiceAddress, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	client := aipb.NewAIServiceClient(conn)

	// レポート生成リクエストの作成
	req := &aipb.GenerateReportRequest{
		UserId:       "system",
		Instructions: instructions,
		Data:         "",
		Context:      "",
	}
	stream, err := client.GenerateReport(context.Background(), req)
	if err != nil {
		return nil, err
	}

	fmt.Println("レポート生成を開始します...")
	var finalReport *aipb.Report
	for {
		res, err := stream.Recv()
		if err == io.EOF {
			fmt.Println("レポート生成が完了しました。")
			break
		}
		if err != nil {
			return nil, err
		}

		if res.GetTasks() != "" {
			fmt.Printf("タスク: %s\n", res.GetTasks())
		}
		if res.GetThinking() != "" {
			fmt.Printf("思考: %s\n", res.GetThinking())
		}
		if res.GetReport() != nil {
			fmt.Printf("レポートタイトル: %s\n", res.GetReport().GetTitle())
			fmt.Printf("レポート本文:\n%s\n", res.GetReport().GetBody())
			finalReport = res.GetReport()
		}
	}
	return finalReport, nil
}

// PersistReport は生成されたレポートをreport-serviceを通じて永続化します。
func PersistReport(reportReq *reportpb.CreateReportRequest) error {
	conn, err := grpc.NewClient(reportServiceAddress, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	defer conn.Close()
	client := reportpb.NewReportServiceClient(conn)

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	res, err := client.CreateReport(ctx, reportReq)
	if err != nil {
		return err
	}

	if !res.GetSuccess() {
		return fmt.Errorf("レポートの永続化が失敗しました: %s", res.GetMessage())
	}

	fmt.Printf("レポートが正常に永続化されました。Report ID: %s\n", res.GetReport().GetReportId())
	return nil
}

func main() {
	instructions := "過去24時間のシステムパフォーマンスに関する詳細なレポートを作成してください。特にCPU使用率とメモリ使用率に焦点を当ててください。"
	aiReport, err := GenerateReportFromInstructions(instructions)
	if err != nil || aiReport == nil {
		log.Fatalf("レポート生成に失敗しました: %v", err)
	}

	// レポートを永続化
	createReportReq := &reportpb.CreateReportRequest{
		ReportId:    fmt.Sprintf("report-%d", time.Now().UnixNano()),
		ReportBody:  aiReport.GetBody(),
		UserId:      "system", // AIサービスのUserIdを使用
		ReportTitle: aiReport.GetTitle(),
		ReportType:  "job",
		Status:      "completed",
		Severity:    reportpb.Severity_LOW,
	}
	if err = PersistReport(createReportReq); err != nil {
		log.Fatalf("レポートの永続化に失敗しました: %v", err)
	}
}
