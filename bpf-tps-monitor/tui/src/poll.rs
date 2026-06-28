//! HTTP polling + JSON schema definition.
//!
//! Wire format is documented in the repo-wide README (`/metrics` JSON schema).
//! All fields are `Option<T>` for forward-compatibility with new collector
//! releases — older fields are simply ignored if absent.

use anyhow::{Context, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)] // many fields are kept for forward-compat / future rendering
pub struct Metrics {
    /// Unix timestamp (seconds) at which the collector sampled this window.
    #[serde(default)]
    pub ts: Option<i64>,

    /// Window size used by the collector (typically 1 s).
    #[serde(default)]
    pub window_secs: Option<u64>,

    /// Packet count during the current/most-recent window (per direction).
    #[serde(default)]
    pub in_packets: Option<u64>,
    #[serde(default)]
    pub out_packets: Option<u64>,

    /// Byte count during the current/most-recent window (per direction).
    #[serde(default)]
    pub in_bytes: Option<u64>,
    #[serde(default)]
    pub out_bytes: Option<u64>,

    /// Instantaneous transactions-per-second for the most-recent window.
    #[serde(default)]
    pub in_tps: Option<f64>,
    #[serde(default)]
    pub out_tps: Option<f64>,
    #[serde(default)]
    pub total_tps: Option<f64>,

    /// M3UA traffic-class distribution for the current second.
    #[serde(default)]
    pub by_class: Option<HashMap<String, u64>>,

    /// Top SCTP streams by packet count (forward-compat hint).
    #[serde(default)]
    pub top_streams: Option<Vec<TopStream>>,

    /// Interfaces being monitored (forward-compat hint).
    #[serde(default)]
    pub interfaces: Option<Vec<String>>,

    /// Cumulative counters since collector start.
    #[serde(default)]
    pub cumulative: Option<Cumulative>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(dead_code)]
pub struct TopStream {
    pub stream_id: u32,
    #[serde(default)]
    pub in_packets: u64,
    #[serde(default)]
    pub out_packets: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Cumulative {
    #[serde(default)]
    pub in_packets: u64,
    #[serde(default)]
    pub out_packets: u64,
    #[serde(default)]
    pub in_bytes: u64,
    #[serde(default)]
    pub out_bytes: u64,
}

#[allow(dead_code)]
impl Metrics {
    /// Total TPS — `total_tps` field if present, else sum of in/out.
    pub fn total_tps(&self) -> f64 {
        self.total_tps
            .unwrap_or_else(|| self.in_tps.unwrap_or(0.0) + self.out_tps.unwrap_or(0.0))
    }

    pub fn class_count(&self, name: &str) -> u64 {
        self.by_class
            .as_ref()
            .and_then(|m| m.get(name).copied())
            .unwrap_or(0)
    }

    pub fn class_total(&self) -> u64 {
        self.by_class
            .as_ref()
            .map(|m| m.values().copied().sum())
            .unwrap_or(0)
    }
}

/// Cheap-to-clone handle to the collector. The inner HTTP client is
/// reference-counted so we can pass a handle into a `tokio::spawn`'d
/// task without moving the whole `App` across threads.
#[derive(Clone)]
pub struct CollectorClient {
    inner: Arc<CollectorClientInner>,
}

struct CollectorClientInner {
    base: String,
    http: reqwest::Client,
}

impl CollectorClient {
    pub fn new(base: impl Into<String>) -> Result<Self> {
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(3))
            .connect_timeout(Duration::from_secs(2))
            .user_agent(concat!("sctp-m3ua-tui/", env!("CARGO_PKG_VERSION")))
            .build()
            .context("building reqwest client")?;
        Ok(Self {
            inner: Arc::new(CollectorClientInner {
                base: base.into().trim_end_matches('/').to_string(),
                http,
            }),
        })
    }

    /// Fetch `/metrics` and decode into `Metrics`. Returns a descriptive
    /// `anyhow::Error` on transport or schema failure.
    pub async fn fetch(&self) -> Result<Metrics> {
        let url = format!("{}/metrics", self.inner.base);
        let resp = self
            .inner
            .http
            .get(&url)
            .send()
            .await
            .with_context(|| format!("GET {url}"))?;

        let status = resp.status();
        if !status.is_success() {
            anyhow::bail!("collector returned HTTP {}", status.as_u16());
        }

        let body = resp
            .text()
            .await
            .context("reading collector response body")?;

        serde_json::from_str::<Metrics>(&body)
            .with_context(|| format!("parsing /metrics JSON from {url}"))
    }

    pub fn clone_arc(&self) -> Arc<Self> {
        Arc::new(self.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_minimal_payload() {
        let j = r#"{
            "ts": 1719581234,
            "window_secs": 1,
            "in_packets": 1234, "out_packets": 1235,
            "in_bytes": 56789, "out_bytes": 56780,
            "in_tps": 1234.0, "out_tps": 1235.0, "total_tps": 2469.0,
            "by_class": {"transfer":1100,"snm":5,"aspsm":2,"asptm":0,"mgmt":127,"other":0},
            "cumulative": {"in_packets":1,"out_packets":2,"in_bytes":3,"out_bytes":4}
        }"#;
        let m: Metrics = serde_json::from_str(j).unwrap();
        assert_eq!(m.total_tps(), 2469.0);
        assert_eq!(m.class_count("transfer"), 1100);
        assert_eq!(m.class_total(), 1234);
    }

    #[test]
    fn forward_compat_with_unknown_fields() {
        let j = r#"{ "total_tps": 1.0, "future_field": [1,2,3] }"#;
        let m: Metrics = serde_json::from_str(j).unwrap();
        assert_eq!(m.total_tps(), 1.0);
    }
}
