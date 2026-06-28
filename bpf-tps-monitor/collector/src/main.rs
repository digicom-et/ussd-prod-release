//! `sctp-m3ua-collector` — AF_PACKET SCTP/M3UA capture daemon.
//!
//! Usage:
//!   sctp-m3ua-collector --bind 0.0.0.0:9090 --iface eth0 --gw-port 8012 \
//!                        --window-secs 1
//!
//! The collector opens a raw `AF_PACKET` socket, installs a BPF filter for
//! IPv4/SCTP, parses each frame, classifies DATA chunks relative to the
//! gateway SCTP port, and exposes rolling-window TPS metrics over HTTP/JSON.

use std::net::SocketAddr;
use std::str::FromStr;

use anyhow::{Context, Result};
use clap::Parser;
use tokio::signal::unix::{signal, SignalKind};
use tracing::{error, info};
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

mod collector;
mod http;
mod metrics;

use crate::collector::spawn_capture;
use crate::metrics::Metrics;

#[derive(Debug, Parser)]
#[command(
    name = "sctp-m3ua-collector",
    version,
    about = "AF_PACKET SCTP/M3UA collector exposing TPS metrics over HTTP/JSON",
    long_about = None
)]
struct Cli {
    /// HTTP bind address, e.g. `0.0.0.0:9090`.
    #[arg(long, default_value = "0.0.0.0:9090")]
    bind: String,

    /// Interface to capture on (e.g. `eth0`). Use `any` for all interfaces.
    #[arg(long, default_value = "any")]
    iface: String,

    /// Rolling window length in seconds.
    #[arg(long, default_value_t = 1)]
    window_secs: u64,

    /// SCTP port of the gateway. Packets with src or dst port equal to this
    /// are classified as `out`/`in`; everything else is ignored.
    #[arg(long, default_value_t = 8012)]
    gw_port: u16,

    /// Number of top streams to surface in `/metrics`.
    #[arg(long, default_value_t = 5)]
    top_streams: usize,

    /// Verbosity filter, e.g. `info`, `debug`, `sctp_m3ua_collector=debug`.
    #[arg(long, default_value = "info")]
    log_filter: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    // Tracing → stderr (so docker logs / kubectl logs work out of the box).
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new(cli.log_filter.clone()));
    tracing_subscriber::registry()
        .with(filter)
        .with(fmt::layer().with_writer(std::io::stderr).with_target(false))
        .init();

    info!(
        version = env!("CARGO_PKG_VERSION"),
        bind = %cli.bind,
        iface = %cli.iface,
        gw_port = cli.gw_port,
        window_secs = cli.window_secs,
        "starting sctp-m3ua-collector"
    );

    // Parse bind address.
    let bind = SocketAddr::from_str(&cli.bind).context("invalid --bind address")?;
    if bind.port() == 0 {
        anyhow::bail!("--bind must include a non-zero port");
    }

    // Shared metrics handle.
    let iface_name = if cli.iface == "any" { None } else { Some(cli.iface.clone()) };
    let metrics = Metrics::new(cli.window_secs, iface_name.as_deref().unwrap_or("any"));

    // Spawn capture loop on the blocking thread pool.
    let capture_metrics = metrics.clone();
    let capture_iface = iface_name.clone();
    let gw_port = cli.gw_port;
    // Keep the JoinHandle alive for the lifetime of main(): the blocking
    // thread is intentionally detached. The AF_PACKET socket is cleaned up
    // by the kernel when the process exits.
    let _capture_handle = spawn_capture(capture_metrics, capture_iface, gw_port);

    // Install SIGINT/SIGTERM handler so docker stop cleanly drains.
    let mut sigterm = signal(SignalKind::terminate()).context("install SIGTERM handler")?;
    let mut sigint = signal(SignalKind::interrupt()).context("install SIGINT handler")?;

    // HTTP server. Axum's serve future resolves only on error; we wrap it
    // in a select! against the shutdown signal.
    let http_metrics = metrics.clone();
    let http_task = tokio::spawn(async move {
        if let Err(e) = http::serve(bind, http_metrics).await {
            error!(error = %e, "http server crashed");
        }
    });

    tokio::select! {
        _ = sigterm.recv() => info!("received SIGTERM, shutting down"),
        _ = sigint.recv()  => info!("received SIGINT, shutting down"),
    }

    // Abort the HTTP server; the capture thread is intentionally detached.
    http_task.abort();
    info!("bye");
    Ok(())
}
