# ベースイメージとしてRustの公式イメージを使用
FROM rust:1.90.0-slim-bookworm AS builder

# 作業ディレクトリを設定
WORKDIR /app

# Cargo.tomlとCargo.lockをコピーして依存関係をキャッシュ
COPY Cargo.toml Cargo.lock ./
# ビルド依存関係を解決するためにダミーのsrc/main.rsを作成
RUN mkdir src && echo "fn main() {}" > src/main.rs
# protobuf-compilerをインストール
RUN apt-get update && apt-get install -y protobuf-compiler && rm -rf /var/lib/apt/lists/*
# 依存関係をビルド
RUN cargo build --release --bin api-gateway-service || true
# ダミーのsrc/main.rsを削除
RUN rm src/main.rs

# ソースコードをコピー
COPY build.rs ./build.rs
COPY src ./src

# gRPCプロトコルファイルをコピー
COPY proto ./proto

# gRPCクライアントコードを生成
RUN cargo build --release --bin api-gateway-service

# 最終的な実行イメージ
FROM debian:bookworm-slim

# タイムゾーンを設定
ENV TZ=Asia/Tokyo
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 必要なライブラリをインストール
RUN apt-get update && apt-get install -y \
    libssl-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ビルダーイメージからコンパイル済みのバイナリをコピー
COPY --from=builder /app/target/release/api-gateway-service /usr/local/bin/api-gateway-service

# 実行可能ファイルに権限を付与
RUN chmod +x /usr/local/bin/api-gateway-service

# ポートを公開
EXPOSE 8000

# アプリケーションを実行
CMD ["/usr/local/bin/api-gateway-service"]
