//! Rolling-window metrics for SCTP/M3UA traffic.
//!
//! Two layers:
//!   * `Metrics`       — thread-safe handle shared between the packet reader
//!                       and the HTTP server.
//!   * `WindowAggregator` — per-second `WindowSample`s kept in a `VecDeque`,
//!     rotated every wall-clock second. The HTTP layer reads this to compute
//!     `in_tps` / `out_tps` / `total_tps` for the last N seconds.
//!
//! All counters are guarded by a `parking_lot::Mutex` (cheap, non-async) and
//! shared via `Arc`.

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use parking_lot::Mutex;
use serde::Serialize;

/// Per-second bucket.
#[derive(Debug, Clone, Default, Serialize)]
pub struct WindowSample {
    /// Wall-clock second (epoch seconds) this bucket represents.
    pub ts: u64,
    pub in_packets: u64,
    pub out_packets: u64,
    pub in_bytes: u64,
    pub out_bytes: u64,
    /// M3UA message class breakdown.
    pub by_class: HashMap<String, u64>,
    /// Per-stream-id counts (top-N surfaced later).
    pub per_stream_in: HashMap<u16, u64>,
    pub per_stream_out: HashMap<u16, u64>,
}

impl WindowSample {
    fn new(ts: u64) -> Self {
        Self {
            ts,
            ..Default::default()
        }
    }
}

/// M3UA message class names (RFC 4666 §4).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum M3uaClass {
    Mgmt,     // 0 — Management
    Transfer, // 1 — Transfer messages
    Snm,      // 2 — Signalling Network Management
    Aspsm,    // 3 — ASP State Maintenance
    Asptm,    // 4 — ASP Traffic Maintenance
    Other,    // 5+
}

impl M3uaClass {
    pub fn from_u8(v: u8) -> Self {
        match v {
            0 => Self::Mgmt,
            1 => Self::Transfer,
            2 => Self::Snm,
            3 => Self::Aspsm,
            4 => Self::Asptm,
            _ => Self::Other,
        }
    }
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Mgmt => "mgmt",
            Self::Transfer => "transfer",
            Self::Snm => "snm",
            Self::Aspsm => "aspsm",
            Self::Asptm => "asptm",
            Self::Other => "other",
        }
    }
}

/// Snapshot of the rolling-window metrics returned to the TUI agent.
#[derive(Debug, Serialize)]
pub struct MetricsSnapshot {
    pub ts: u64,
    pub window_secs: u64,
    pub in_packets: u64,
    pub out_packets: u64,
    pub in_bytes: u64,
    pub out_bytes: u64,
    pub in_tps: f64,
    pub out_tps: f64,
    pub total_tps: f64,
    pub by_class: HashMap<String, u64>,
    pub top_streams: Vec<StreamStat>,
    pub interfaces: Vec<String>,
    pub cumulative: Cumulative,
}

#[derive(Debug, Serialize)]
pub struct StreamStat {
    pub stream_id: u16,
    pub in_packets: u64,
    pub out_packets: u64,
}

#[derive(Debug, Default, Serialize, Clone)]
pub struct Cumulative {
    pub in_packets: u64,
    pub out_packets: u64,
    pub in_bytes: u64,
    pub out_bytes: u64,
}

#[derive(Debug)]
pub struct WindowAggregator {
    pub window_secs: u64,
    pub max_history: usize,
    pub current: WindowSample,
    pub history: VecDeque<WindowSample>,
    pub interfaces: Vec<String>,
    pub cumulative: Cumulative,
    pub start_ts: u64,
}

impl WindowAggregator {
    pub fn new(window_secs: u64, iface: &str) -> Self {
        let now = now_secs();
        Self {
            window_secs,
            max_history: 600, // up to 10 minutes of 1-second buckets
            current: WindowSample::new(now),
            history: VecDeque::new(),
            interfaces: vec![iface.to_string()],
            cumulative: Cumulative::default(),
            start_ts: now,
        }
    }

    /// Roll the active bucket forward if we crossed into a new wall-clock second.
    fn maybe_rotate(&mut self, now: u64) {
        if now != self.current.ts {
            let finished = std::mem::replace(&mut self.current, WindowSample::new(now));
            self.history.push_back(finished);
            while self.history.len() > self.max_history {
                self.history.pop_front();
            }
        }
    }

    /// Record one DATA chunk.
    pub fn record(
        &mut self,
        direction: Direction,
        bytes: u64,
        stream_id: u16,
        class: Option<M3uaClass>,
    ) {
        let now = now_secs();
        self.maybe_rotate(now);

        match direction {
            Direction::In => {
                self.current.in_packets += 1;
                self.current.in_bytes += bytes;
                self.cumulative.in_packets += 1;
                self.cumulative.in_bytes += bytes;
                *self.current.per_stream_in.entry(stream_id).or_insert(0) += 1;
            }
            Direction::Out => {
                self.current.out_packets += 1;
                self.current.out_bytes += bytes;
                self.cumulative.out_packets += 1;
                self.cumulative.out_bytes += bytes;
                *self.current.per_stream_out.entry(stream_id).or_insert(0) += 1;
            }
        }

        if let Some(c) = class {
            *self.current.by_class.entry(c.as_str().to_string()).or_insert(0) += 1;
        }
    }

    /// Build the JSON snapshot for the TUI agent.
    pub fn snapshot(&self, top_n: usize) -> MetricsSnapshot {
        let now = now_secs();

        // Sum last `window_secs` buckets. The active one counts as the in-flight
        // second; we always include it.
        let mut win_in_packets: u64 = self.current.in_packets;
        let mut win_out_packets: u64 = self.current.out_packets;
        let mut win_in_bytes: u64 = self.current.in_bytes;
        let mut win_out_bytes: u64 = self.current.out_bytes;
        let mut by_class: HashMap<String, u64> = self.current.by_class.clone();
        let mut per_stream_in: HashMap<u16, u64> = self.current.per_stream_in.clone();
        let mut per_stream_out: HashMap<u16, u64> = self.current.per_stream_out.clone();

        for sample in self.history.iter().rev().take(self.window_secs as usize) {
            win_in_packets += sample.in_packets;
            win_out_packets += sample.out_packets;
            win_in_bytes += sample.in_bytes;
            win_out_bytes += sample.out_bytes;
            for (k, v) in &sample.by_class {
                *by_class.entry(k.clone()).or_insert(0) += v;
            }
            for (k, v) in &sample.per_stream_in {
                *per_stream_in.entry(*k).or_insert(0) += v;
            }
            for (k, v) in &sample.per_stream_out {
                *per_stream_out.entry(*k).or_insert(0) += v;
            }
        }

        let secs = self.window_secs.max(1) as f64;
        let in_tps = win_in_packets as f64 / secs;
        let out_tps = win_out_packets as f64 / secs;

        // Build top streams by total traffic.
        let mut all_streams: HashMap<u16, (u64, u64)> = HashMap::new();
        for (sid, c) in &per_stream_in {
            all_streams.entry(*sid).or_insert((0, 0)).0 = *c;
        }
        for (sid, c) in &per_stream_out {
            all_streams.entry(*sid).or_insert((0, 0)).1 = *c;
        }
        let mut top: Vec<StreamStat> = all_streams
            .into_iter()
            .map(|(stream_id, (in_packets, out_packets))| StreamStat {
                stream_id,
                in_packets,
                out_packets,
            })
            .collect();
        top.sort_by(|a, b| {
            let at = a.in_packets + a.out_packets;
            let bt = b.in_packets + b.out_packets;
            bt.cmp(&at)
        });
        top.truncate(top_n);

        // Ensure all M3UA class keys are present even if zero (contract).
        for k in ["transfer", "snm", "aspsm", "asptm", "mgmt", "other"] {
            by_class.entry(k.to_string()).or_insert(0);
        }

        MetricsSnapshot {
            ts: now,
            window_secs: self.window_secs,
            in_packets: win_in_packets,
            out_packets: win_out_packets,
            in_bytes: win_in_bytes,
            out_bytes: win_out_bytes,
            in_tps,
            out_tps,
            total_tps: in_tps + out_tps,
            by_class,
            top_streams: top,
            interfaces: self.interfaces.clone(),
            cumulative: Cumulative {
                in_packets: self.cumulative.in_packets,
                out_packets: self.cumulative.out_packets,
                in_bytes: self.cumulative.in_bytes,
                out_bytes: self.cumulative.out_bytes,
            },
        }
    }

    pub fn uptime_secs(&self) -> u64 {
        now_secs().saturating_sub(self.start_ts)
    }
}

/// Direction of a DATA chunk relative to the gateway.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    /// Packet destined to the gateway (dst_port == gw_port).
    In,
    /// Packet originating from the gateway (src_port == gw_port).
    Out,
}

/// Thread-safe handle.
#[derive(Debug, Clone)]
pub struct Metrics {
    inner: Arc<Mutex<WindowAggregator>>,
}

impl Metrics {
    pub fn new(window_secs: u64, iface: &str) -> Self {
        Self {
            inner: Arc::new(Mutex::new(WindowAggregator::new(window_secs, iface))),
        }
    }

    pub fn record(
        &self,
        direction: Direction,
        bytes: u64,
        stream_id: u16,
        class: Option<M3uaClass>,
    ) {
        self.inner.lock().record(direction, bytes, stream_id, class);
    }

    pub fn snapshot(&self, top_n: usize) -> MetricsSnapshot {
        self.inner.lock().snapshot(top_n)
    }

    pub fn uptime_secs(&self) -> u64 {
        self.inner.lock().uptime_secs()
    }
}

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_snapshot_returns_zero_tps() {
        let m = Metrics::new(1, "eth0");
        let s = m.snapshot(5);
        assert_eq!(s.in_packets, 0);
        assert_eq!(s.out_packets, 0);
        assert!(s.total_tps.abs() < f64::EPSILON);
        assert!(s.by_class.contains_key("transfer"));
    }

    #[test]
    fn record_increments_counters() {
        let m = Metrics::new(1, "eth0");
        m.record(Direction::In, 100, 1, Some(M3uaClass::Transfer));
        m.record(Direction::Out, 200, 1, Some(M3uaClass::Snm));
        let s = m.snapshot(5);
        assert_eq!(s.in_packets, 1);
        assert_eq!(s.out_packets, 1);
        assert_eq!(s.in_bytes, 100);
        assert_eq!(s.out_bytes, 200);
        assert_eq!(*s.by_class.get("transfer").unwrap(), 1);
        assert_eq!(*s.by_class.get("snm").unwrap(), 1);
    }

    #[test]
    fn top_streams_sorted_by_traffic() {
        let m = Metrics::new(1, "eth0");
        m.record(Direction::In, 1, 7, None);
        m.record(Direction::Out, 1, 7, None);
        m.record(Direction::In, 1, 3, None);
        let s = m.snapshot(5);
        assert_eq!(s.top_streams[0].stream_id, 7);
    }

    #[test]
    fn class_from_u8() {
        assert_eq!(M3uaClass::from_u8(0), M3uaClass::Mgmt);
        assert_eq!(M3uaClass::from_u8(1), M3uaClass::Transfer);
        assert_eq!(M3uaClass::from_u8(4), M3uaClass::Asptm);
        assert_eq!(M3uaClass::from_u8(5), M3uaClass::Other);
    }
}
