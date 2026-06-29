# syntax=docker/dockerfile:1.7
# Multi-stage build for the SCTP/M3UA TPS TUI dashboard.
# Stage 1 compiles a static musl binary; stage 2 ships a ~10 MB
# Alpine runtime that contains nothing but ca-certificates + tzdata
# plus the binary.

# ============================================================
# Stage 1 — builder
# ============================================================
FROM rust:alpine AS builder

ENV CARGO_TERM_COLOR=always \
    RUSTFLAGS="-C target-feature=+crt-static -C link-arg=-s"

RUN apk add --no-cache \
        musl-dev \
        pkgconfig \
        openssl-dev \
        openssl-libs-static

WORKDIR /build

# Cache deps separately from sources.
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && \
    echo "fn main() { println!(\"placeholder\"); }" > src/main.rs && \
    cargo build --release --target x86_64-unknown-linux-musl && \
    rm -rf src target/x86_64-unknown-linux-musl/release/deps/tui*

# Real sources.
COPY src ./src
RUN cargo build --release --target x86_64-unknown-linux-musl

# ============================================================
# Stage 2 — runtime
# ============================================================
FROM alpine:3.19

RUN apk add --no-cache \
        ca-certificates \
        tzdata \
    && update-ca-certificates

# Run as non-root for defense in depth.
RUN addgroup -S tui && adduser -S tui -G tui

WORKDIR /app

COPY --from=builder \
    /build/target/x86_64-unknown-linux-musl/release/tui \
    /app/tui

USER tui

# TERM is required by ratatui/crossterm to negotiate cursor modes.
ENV TERM=xterm-256color \
    COLORTERM=truecolor

# Default arguments — compose overrides these; kept as fallback for `docker run` usage.
ENTRYPOINT ["/app/tui"]
CMD ["--collector", "http://127.0.0.1:9090"]
