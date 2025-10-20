# Stage 1: Builder
FROM rust:1.82-bullseye AS builder

RUN apt-get update && apt-get install -y \
    build-essential \
    perl \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy Cargo.toml and Cargo.lock to leverage Docker cache
COPY Cargo.toml ./

# Build dummy dependencies to cache them
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

# Copy the actual source code
COPY src ./src

CMD ["cargo", "run"]
