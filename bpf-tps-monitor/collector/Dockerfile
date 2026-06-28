# syntax=docker/dockerfile:1.6
# Multi-stage build for sctp-m3ua-collector.
# Result: a static musl-linked binary running as nobody on alpine.

FROM rust:1.78-alpine3.19 AS builder
RUN apk add --no-cache musl-dev linux-headers pkgconfig
WORKDIR /build
# Pre-cache dependencies separately for faster incremental builds.
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && echo 'fn main(){}' > src/main.rs && \
    RUSTFLAGS="-C target-feature=+crt-static" \
    cargo build --release --target x86_64-unknown-linux-musl && \
    rm -rf src target/x86_64-unknown-linux-musl/release/deps/sctp_m3ua_collector*

COPY src ./src
RUN RUSTFLAGS="-C target-feature=+crt-static" \
    cargo build --release --target x86_64-unknown-linux-musl

FROM alpine:3.19
RUN apk add --no-cache ca-certificates tzdata libgcc
COPY --from=builder /build/target/x86_64-unknown-linux-musl/release/sctp-m3ua-collector /usr/local/bin/collector
USER 65534:65534
EXPOSE 9090
ENTRYPOINT ["/usr/local/bin/collector"]
