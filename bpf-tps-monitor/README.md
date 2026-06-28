# SCTP/M3UA TPS Monitor

Live transactions-per-second dashboard for the USSD Gateway's SCTP / M3UA
signalling plane. A Rust eBPF-based **collector** taps the SGW-facing
interface, aggregates per-second packet and byte counters, classifies M3UA
traffic by message class, and exposes a single JSON endpoint on
`http://localhost:9090/metrics`. A second Rust **TUI** dashboard
(`ratatui` + `crossterm`) polls that endpoint every second and renders a
fixed, flicker-free, full-screen dashboard.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ USSD GW SCTP/M3UA TPS Monitor ─ collector: http://collector:9090  Uptime …  │
├──────────────────────────────────┬──────────────────────────────────────────┤
│ TPS (in/out/total)               │ M3UA by class (current second)          │
│   Now      :  in=1234.5 out=…    │   transfer      [████████░░░] 89%        │
│   Avg 60s  :  …                  │   snm           [█░░░░░░░░░░]  0%        │
│   Peak 60s :  …                  │   aspsm / asptm / mgmt / other …        │
│                                  │                                          │
│ Packet counters (cumulative)     │                                          │
│   IN/OUT packets, MB             │                                          │
├──────────────────────────────────┴──────────────────────────────────────────┤
│ TPS over last 60s (sparkline)                                                │
├─────────────────────────────────────────────────────────────────────────────┤
│ [q] Quit  [r] Reset history  [p] Pause   polling  interval 1000ms  errors: 0 │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Architecture

Two cooperating containers, one shared JSON contract.

```
   ┌──────────────────┐    raw socket / BPF      ┌──────────────────────┐
   │  SGW interface   │ ───────────────────────▶ │  collector container  │
   │  (eth0 on host)  │                          │  - NET_RAW + host net │
   └──────────────────┘                          │  - HTTP :9090/metrics│
                                                 └──────────┬───────────┘
                                                            │ JSON (1 Hz)
                                                            ▼
                                                 ┌──────────────────────┐
                                                 │  tui container        │
                                                 │  - TTY + stdin_open   │
                                                 │  - ratatui dashboard  │
                                                 └──────────────────────┘
```

| Service     | Image                  | Role                                                          |
|-------------|------------------------|---------------------------------------------------------------|
| `collector` | `sctp-m3ua-collector`  | Headless, attaches BPF / raw socket to the SGW interface, publishes `/metrics` JSON every 1 s. |
| `tui`       | `sctp-m3ua-tui`        | Interactive terminal dashboard. Polls `/metrics`, renders in-place. |

## Quick start

Use the **master compose at the package root** — it already wires the
USSD Gateway + BPF collector + TUI together as one stack:

```bash
cd /opt/ussdgw-prod-release              # package root

# Way A: One command — gateway + collector daemon, TUI foreground (auto-attach):
docker compose -f docker-compose.yml up -d ussdgw collector
docker compose -f docker-compose.yml up tui

# Way B: All in one (foreground):
docker compose -f docker-compose.yml up

# Way C: Use the helper scripts:
./scripts/03-start-gateway.sh --with-monitor   # gateway + collector daemon
./scripts/03-start-gateway.sh --tui-only       # attach TUI to this terminal

# Detach the TUI without killing it: Ctrl-p Ctrl-q
# Re-attach later:  docker attach sctp-m3ua-tui
```

The TUI is built for **interactive** use; the collector is **headless**.
See *Why two containers?* below.

If you want to run just the monitor stack (without the gateway), the
per-app `docker-compose.yml` files were kept as
`bpf-tps-monitor/docker-compose.yml.standalone.bak` for reference —
but the recommended path is the master compose.

## `/metrics` JSON schema

The TUI and the collector agree on this contract. All fields are
optional on the client side (forward-compatible), but the collector
emits all of them every second.

```jsonc
{
  "ts":           1719581234,
  "window_secs":  1,
  "in_packets":   1234,  "out_packets": 1235,
  "in_bytes":     56789, "out_bytes":   56780,
  "in_tps":       1234.0, "out_tps":    1235.0, "total_tps": 2469.0,
  "by_class": {
    "transfer": 1100, "snm": 5, "aspsm": 2, "asptm": 0, "mgmt": 127, "other": 0
  },
  "top_streams": [ { "stream_id": 1, "in_packets": 600, "out_packets": 600 } ],
  "interfaces":  ["eth0"],
  "cumulative": {
    "in_packets":  12345678, "out_packets": 12340123,
    "in_bytes":    567890123, "out_bytes":  567450000
  }
}
```

If a field is missing, the TUI degrades gracefully (renders `—` and
keeps the last good values on screen).

## TUI key bindings

| Key            | Action                                                      |
|----------------|-------------------------------------------------------------|
| `q` / `Esc`    | Quit (restores the main screen and shows the cursor).      |
| `Ctrl+C`       | Same as `q`.                                                |
| `p`            | Pause / resume polling. The display freezes but stays live. |
| `r`            | Reset the rolling 60-second history.                        |

## Requirements

### Runtime

* Linux host with a kernel ≥ 5.4 (for `BPF_PROG_TYPE_SOCKET_FILTER`).
* Docker Engine ≥ 20.10 with Compose v2.
* Terminal with truecolor support (e.g. `xterm-256color` or any modern
  GNOME / iTerm2 / Windows Terminal).

### Capability requirements

The **collector** must be able to attach a raw socket / load a BPF
program on the SGW-facing interface. The compose file requests:

```yaml
cap_add:
  - NET_RAW          # raw sockets
  - SYS_ADMIN        # BPF prog load + perf event open
  - SYS_RESOURCE     # RLIMIT_MEMLOCK for BPF maps
network_mode: host   # see the SGW interface directly
```

> If your kernel is locked down (`kernel.lockdown=integrity`), you
> must sign the BPF program, or run the collector on the host
> instead of in a container.

The **TUI** has no special capability or network requirements. It
talks to the collector over the default Compose bridge network using
the service name `collector`. `stdin_open: true` + `tty: true` are
mandatory so `docker attach` works.

### Building from source

```bash
cd tui
cargo build --release --target x86_64-unknown-linux-musl   # static binary
strip target/x86_64-unknown-linux-musl/release/tui
```

The release profile in `Cargo.toml` already enables `lto`, `opt-level=z`,
`codegen-units = 1`, `panic = "abort"`, and `strip = true`. A stripped
musl binary lands at roughly **3–5 MB**.

## Why two containers?

A single combined container would have to be both **headless-friendly**
(restart on boot, log to stdout, survive reboots) and **interactive**
(allocate a TTY, accept `q` to quit, redraw 60 times a minute). Those
are conflicting operational profiles:

* **Collector** runs forever. It must hold a raw socket + BPF maps
  for the lifetime of the host. Killing and restarting it on every
  TUI disconnect would drop the rolling counters and break any
  upstream alerting wired to `/metrics`. It is a *service*.
* **TUI** is a *user session*. Operators want to attach, glance at
  the dashboard, and detach — possibly on a workstation, possibly
  over SSH, possibly via `tmux`. The right primitive for that is
  `docker attach` (or `docker compose run --rm`) on a TTY-enabled
  container that can be brought up and down without affecting the
  collector.

Splitting them lets the collector keep its `restart: unless-stopped`
policy and its `NET_RAW` capability, while the TUI stays disposable.
It also makes it trivial to run multiple TUIs (operator workstation,
NOC wall display, CI smoke check) against the same collector.

## Project layout

```
bpf-tps-monitor/
├── docker-compose.yml          # collector + tui services
├── README.md                   # this file
├── collector/                  # headless BPF metrics exporter
│   ├── Cargo.toml
│   └── src/…
└── tui/                        # interactive dashboard
    ├── Cargo.toml
    ├── Dockerfile              # multi-stage musl → alpine
    ├── .dockerignore
    └── src/
        ├── main.rs             # CLI + terminal setup/teardown
        ├── app.rs              # rolling history + state
        ├── ui.rs               # ratatui layout & widgets
        └── poll.rs             # HTTP client + JSON schema
```

## Troubleshooting

| Symptom                                                | Likely cause / fix |
|--------------------------------------------------------|--------------------|
| TUI shows `Collector unreachable, retrying…`           | Collector not up, or `--collector` URL wrong. Try `curl $URL/metrics` from inside the TUI container. |
| Yellow `errors: N` counter incrementing                | Transient network blips. Persistent? Check collector health with `docker inspect sctp-m3ua-collector`. |
| TUI exits immediately                                  | Terminal too small. Need ≥ 24 rows × 80 cols, or your terminal doesn't support the alternate screen. |
| `failed to load BPF program` from collector            | Missing capabilities, or kernel lockdown. Re-check `cap_add` and `/sys/kernel/debug` mount. |
| Sparkline blank / always 0                             | Collector is publishing but `total_tps` is `0`. Check the by-class counts — traffic may be all `mgmt` with no `transfer` (idle SGW). |
