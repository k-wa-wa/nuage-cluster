# Stage 1: Builder
# Stage 1: Builder
FROM rust:1.82-slim-bullseye AS builder

# Install musl-tools for static linking
RUN apt-get update && apt-get install -y musl-tools libssl-dev pkg-config && rm -rf /var/lib/apt/lists/*
RUN rustup target add x86_64-unknown-linux-musl

WORKDIR /app

# Copy Cargo.toml and Cargo.lock to leverage Docker cache
COPY Cargo.toml Cargo.lock ./

# Build dummy dependencies to cache them
RUN mkdir src && echo "fn main() {}" > src/main.rs
ENV RUSTFLAGS="-C target-feature=+crt-static"
RUN cargo build --release --target x86_64-unknown-linux-musl
RUN rm -rf src

# Copy the actual source code
COPY src ./src

# Build the application with static linking
RUN cargo build --release --target x86_64-unknown-linux-musl

# Stage 2: Runtime
FROM scratch AS runtime

WORKDIR /app

# Copy the compiled binary from the builder stage
COPY --from=builder /app/target/x86_64-unknown-linux-musl/release/gateway-rs ./gateway-rs

# Expose the port the application listens on (assuming 8080 as a common default for actix-web)
EXPOSE 8080

# Run the application
CMD ["./gateway-rs"]
