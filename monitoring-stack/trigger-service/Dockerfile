FROM golang:1.24.2-bookworm AS builder

WORKDIR /app
ENV CGO_ENABLED=0

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
RUN go build -o trigger-service .

FROM scratch AS runner

WORKDIR /app
COPY --from=builder /app/trigger-service .

CMD ["/app/trigger-service"]
