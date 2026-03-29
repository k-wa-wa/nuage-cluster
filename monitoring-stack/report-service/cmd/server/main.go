package main

import (
	"context"
	"log"
	"net"
	"net/http"
	"report-service/internal/pb"
	"report-service/internal/service"

	"google.golang.org/grpc"
)

const (
	grpcPort = ":5051"
	httpPort = ":5052"
)

func main() {
	ctx := context.Background()

	// 1. サービスインスタンスの作成
	reportService, err := service.NewReportService(ctx)
	if err != nil {
		log.Fatalf("Failed to initialize Report Service: %v", err)
	}

	// 2. HTTP サーバーを goroutine で起動 (Grafana 連携用)
	go func() {
		mux := http.NewServeMux()
		// エンドポイントの定義
		mux.HandleFunc("GET /api/v1/reports", reportService.HandleListReports)
		mux.HandleFunc("GET /api/v1/reports/{id}/details", reportService.HandleGetReportDetails)

		log.Printf("Report HTTP API listening at %s", httpPort)
		if err := http.ListenAndServe(httpPort, mux); err != nil {
			log.Fatalf("failed to serve http: %v", err)
		}
	}()

	// 3. gRPC サーバーの起動
	lis, err := net.Listen("tcp", grpcPort)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterReportServiceServer(s, reportService)

	log.Printf("Report gRPC Service listening at %v", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve grpc: %v", err)
	}
}
