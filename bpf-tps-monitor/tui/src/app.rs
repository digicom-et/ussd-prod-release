//! Application state: history buffer, latest snapshot, error counter,
//! pause flag, and the polling client.

use crate::poll::{CollectorClient, Metrics};
use anyhow::Result;
use std::collections::{HashMap, VecDeque};
use std::time::Instant;

const HISTORY_LEN: usize = 60;

#[derive(Debug, Clone, Copy)]
pub struct TpsSample {
    pub total_tps: f64,
    pub in_tps: f64,
    pub out_tps: f64,
}

pub struct App {
    pub collector_url: String,
    pub client: CollectorClient,
    pub started_at: Instant,

    pub history: VecDeque<TpsSample>,
    pub latest: Option<Metrics>,
    pub errors: u32,
    pub paused: bool,
    pub interval_ms: u64,
    pub last_poll_at: Option<Instant>,

    /// Peak over the current history window (recomputed on insert).
    pub peak_total: f64,
    pub peak_in: f64,
    pub peak_out: f64,

    /// Cumulative rolling sums for the avg computation.
    pub sum_total: f64,
    pub sum_in: f64,
    pub sum_out: f64,
}

impl App {
    pub fn new(collector_url: String, interval_ms: u64) -> Result<Self> {
        let client = CollectorClient::new(&collector_url)?;
        Ok(Self {
            collector_url,
            client,
            started_at: Instant::now(),
            history: VecDeque::with_capacity(HISTORY_LEN),
            latest: None,
            errors: 0,
            paused: false,
            interval_ms,
            last_poll_at: None,
            peak_total: 0.0,
            peak_in: 0.0,
            peak_out: 0.0,
            sum_total: 0.0,
            sum_in: 0.0,
            sum_out: 0.0,
        })
    }

    pub fn uptime(&self) -> std::time::Duration {
        self.started_at.elapsed()
    }

    pub fn avg_total(&self) -> f64 {
        if self.history.is_empty() {
            0.0
        } else {
            self.sum_total / self.history.len() as f64
        }
    }
    pub fn avg_in(&self) -> f64 {
        if self.history.is_empty() {
            0.0
        } else {
            self.sum_in / self.history.len() as f64
        }
    }
    pub fn avg_out(&self) -> f64 {
        if self.history.is_empty() {
            0.0
        } else {
            self.sum_out / self.history.len() as f64
        }
    }

    /// Push a new sample, evict the oldest, and recompute aggregates.
    pub fn push_sample(&mut self, s: TpsSample) {
        if self.history.len() == HISTORY_LEN {
            if let Some(old) = self.history.pop_front() {
                self.sum_total -= old.total_tps;
                self.sum_in -= old.in_tps;
                self.sum_out -= old.out_tps;
            }
        }
        self.history.push_back(s);
        self.sum_total += s.total_tps;
        self.sum_in += s.in_tps;
        self.sum_out += s.out_tps;

        self.peak_total = self.peak_total.max(s.total_tps);
        self.peak_in = self.peak_in.max(s.in_tps);
        self.peak_out = self.peak_out.max(s.out_tps);
    }

    pub fn reset_history(&mut self) {
        self.history.clear();
        self.peak_total = 0.0;
        self.peak_in = 0.0;
        self.peak_out = 0.0;
        self.sum_total = 0.0;
        self.sum_in = 0.0;
        self.sum_out = 0.0;
    }

    /// Pull a fresh sample from the collector. On failure increments
    /// `errors` and returns `Err` — the caller decides whether to log.
    #[allow(dead_code)] // kept for tests / one-off CLI usage
    pub async fn poll(&mut self) -> Result<Metrics> {
        let m = self.client.fetch().await?;
        self.apply_metrics(m.clone());
        Ok(m)
    }

    /// Merge a freshly-fetched `Metrics` snapshot into our rolling state.
    /// Called from the event loop when a background poll task delivers
    /// a result through the channel.
    pub fn apply_metrics(&mut self, m: Metrics) {
        let sample = TpsSample {
            total_tps: m.total_tps(),
            in_tps: m.in_tps.unwrap_or(0.0),
            out_tps: m.out_tps.unwrap_or(0.0),
        };
        self.push_sample(sample);
        self.last_poll_at = Some(Instant::now());
        self.latest = Some(m);
    }

    pub fn record_error(&mut self) {
        self.errors = self.errors.saturating_add(1);
    }

    pub fn toggle_pause(&mut self) {
        self.paused = !self.paused;
    }

    /// Class breakdown as ordered list for stable rendering.
    pub fn ordered_classes(&self) -> Vec<(&'static str, u64)> {
        let order = ["transfer", "snm", "aspsm", "asptm", "mgmt", "other"];
        let m: HashMap<String, u64> = self
            .latest
            .as_ref()
            .and_then(|m| m.by_class.clone())
            .unwrap_or_default();
        order
            .iter()
            .map(|k| (*k, m.get(*k).copied().unwrap_or(0)))
            .collect()
    }

    /// Borrow the inner HTTP client so the loop can call it directly
    /// from a `tokio::spawn`'d task. The client is `Clone` and cheap.
    #[allow(dead_code)] // exposed for future `tokio::spawn` callers
    pub fn client_handle(&self) -> std::sync::Arc<CollectorClient> {
        self.client.clone_arc()
    }
}
