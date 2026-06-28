//! axum-based HTTP server exposing the `/metrics`, `/healthz`, and `/`
//! endpoints consumed by the TUI agent.

use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::{Context, Result};
use axum::{extract::State, http::StatusCode, response::IntoResponse, routing::get, Json, Router};
use serde::Serialize;
use serde_json::json;
use tokio::net::TcpListener;
use tracing::info;

use crate::metrics::Metrics;

/// Number of top streams to surface in `/metrics`. The TUI agent only
/// renders the first few rows anyway; keep this small.
const TOP_STREAMS: usize = 5;

#[derive(Clone)]
struct AppState {
    metrics: Metrics,
}

#[derive(Serialize)]
struct RootInfo {
    service: &'static str,
    version: &'static str,
    uptime_secs: u64,
}

/// Build the axum `Router` with all routes wired up.
fn build_router(state: AppState) -> Router {
    Router::new()
        .route("/", get(root_handler))
        .route("/healthz", get(healthz_handler))
        .route("/metrics", get(metrics_handler))
        .with_state(Arc::new(state))
}

async fn root_handler(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    Json(RootInfo {
        service: "sctp-m3ua-collector",
        version: env!("CARGO_PKG_VERSION"),
        uptime_secs: state.metrics.uptime_secs(),
    })
}

async fn healthz_handler() -> impl IntoResponse {
    (StatusCode::OK, Json(json!({ "ok": true })))
}

async fn metrics_handler(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let snap = state.metrics.snapshot(TOP_STREAMS);
    Json(snap)
}

/// Spawn the HTTP server on the given address. Returns a JoinHandle that
/// resolves when the server stops (which should be never).
pub async fn serve(bind: SocketAddr, metrics: Metrics) -> Result<()> {
    let state = AppState { metrics };
    let router = build_router(state);

    let listener = TcpListener::bind(bind)
        .await
        .with_context(|| format!("bind {bind}"))?;
    info!(%bind, "http server listening");

    axum::serve(listener, router)
        .await
        .context("axum::serve failed")?;
    Ok(())
}
