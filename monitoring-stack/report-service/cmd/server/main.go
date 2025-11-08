package main

import (
	"context"
	"log"
	"net"
	"report-service/internal/pb"
	"report-service/internal/service"

	"google.golang.org/grpc"
)

const port = ":5051" // 内部 gRPC ポート

func main() {
	ctx := context.Background()

	// 1. サービスインスタンスの作成
	reportService, err := service.NewReportService(ctx)
	if err != nil {
		log.Fatalf("Failed to initialize Report Service: %v", err)
	}

	// 2. gRPC サーバーの起動
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	// Istio環境では、セキュリティ設定は Istio Mesh 内で自動的に処理されるため、
	// ここでは標準の gRPC サーバーを使用
	s := grpc.NewServer()
	pb.RegisterReportServiceServer(s, reportService)

	log.Printf("Report Service listening at %v", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
