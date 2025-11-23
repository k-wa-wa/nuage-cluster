FROM golang:1.24.2-bookworm AS builder

WORKDIR /app
ENV CGO_ENABLED=0

COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY proto/ ./proto/

ARG TARGET
RUN go build -o bin ./cmd/${TARGET}


FROM golang:1.24.2-bookworm AS runner
# FROM scratch AS runner

WORKDIR /app
COPY --from=builder /app/bin .

CMD [ "/app/bin" ]
