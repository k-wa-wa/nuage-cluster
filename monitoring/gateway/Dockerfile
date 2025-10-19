# Stage 1: Builder
FROM rust:1.82-bullseye AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    perl \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Cargo.toml and Cargo.lock to leverage Docker cache
COPY Cargo.toml Cargo.lock ./

# Build dummy dependencies to cache them
RUN mkdir src && echo "fn main() {}" > src/main.rs
ENV RUSTFLAGS="-C target-feature=+crt-static"
ENV OPENSSL_STATIC=1
RUN cargo build --release
RUN rm -rf src

# Copy the actual source code
COPY src ./src

# Build the application with static linking
RUN cargo build --release

# Stage 2: Runtime
FROM gcr.io/distroless/cc AS runtime

WORKDIR /app

# Copy the compiled binary from the builder stage
COPY --from=builder /app/target/release/gateway ./gateway

# Expose the port the application listens on (assuming 8080 as a common default for actix-web)
EXPOSE 8080

# Run the application
CMD ["./gateway"]
