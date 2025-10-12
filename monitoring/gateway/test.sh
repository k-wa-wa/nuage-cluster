grpcurl -plaintext --proto proto/report_service.proto -d '{}' localhost:5051 gateway.ReportService/ListReports

grpcurl -plaintext --proto proto/report_service.proto -d '{"report_id": "0fbc3ad7-e940-4f58-b9db-ce8908ec78cb"}' localhost:5051 gateway.ReportService/GetReport
