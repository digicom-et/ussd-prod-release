# USSD Gateway — Prod Release Package

Unpack → run scripts → verify. **No build required.**

---

## Quick Start (copy-paste each step)

### Step 1 — Unpack and enter directory

```bash
cd /opt
tar xzf ussdgw-prod-release-7.3.1.tar.gz
cd ussdgw-prod-release
```

### Step 2 — SCTP + verification

```bash
lsmod | grep sctp          # must see sctp line
# if empty:
sudo modprobe sctp

chmod +x scripts/*.sh
./scripts/00-preflight.sh
```

### Step 3 — Load Docker image (on backup host, without stopping GW)

```bash
./scripts/01-load-docker-image.sh
```

→ Backs up `/opt/ussdgw` (if exists) to `backups/`, loads tar, **keeps old image** for rollback.

### Step 3b — Switch (upgrade) or skip for fresh install

```bash
./scripts/03-switch-gateway.sh
```

### Step 3c — Rollback (if new version is broken)

```bash
./scripts/03-switch-gateway.sh --rollback
sudo ./scripts/02-setup-host.sh --restore backups/ussdgw-<timestamp>/
```

### Step 4 — Setup host

```bash
sudo ./scripts/02-setup-host.sh
```

### Step 5 — Start USSD Gateway (`docker compose up`) ⭐

```bash
./scripts/03-start-gateway.sh                # gateway only
./scripts/03-start-gateway.sh --with-monitor # gateway + BPF collector headless
curl -fs http://localhost:8080/jolokia/version && echo " OK"
```

Or use master compose directly:

```bash
cd ussdgw-prod-release          # stand at package root
docker compose -f docker-compose.yml up -d ussdgw
docker compose -f docker-compose.yml up -d collector   # optional — BPF TPS monitor
```

### Steps 6–9

See `docs/e2e-grpc-ussd-test.md` — each step has a **script** and **「Manual alternative」** (per-tool commands).

| Step | Quick script | Manual tool |
|------|--------------|-------------|
| 6 gRPC AS | `05-start-grpc-as.sh` | `ussd_as_server.py :8443` |
| 7 MAP smoke | `06-run-map-smoke.sh` | `java ... Client ... "*100#" BALANCE` |
| 8 gRPC load | `07-run-grpc-smoke.sh` | `loadtest_client.py` |
| 8b gRPC Push | `14-run-grpc-push-smoke.sh` | `grpc_push_client.py :8453` |
| 9 Stop | `stop-all.sh` | `compose down` + kill AS PID |

Fresh install combined: `sudo ./scripts/start-all.sh`

Full command table: [Appendix A](docs/e2e-grpc-ussd-test.md#phụ-lục-a--chạy-thủ-công-từng-công-cụ-thay-thế-script).

---

## 🛠️ Build from Source (developer)

Use `build-all.sh` to build the entire pipeline from GitHub:

### Prerequisites
- git, mvn, ant, podman/docker
- Java 8 (Zulu) — install via `mise install java@zulu-8`
- Approximately 5 GB disk

### Clone
```bash
git clone <digicom-et-repo-url>
```

### WildFly clean
Download `wildfly-10.0.0.Final.zip` from:
https://download.jboss.org/wildfly/10.0.0.Final/wildfly-10.0.0.Final.zip
Unpack, strip unused modules, save as `resources/wildfly-10.0.0.Final-cleaned.zip`.
Or copy from an existing ussdgateway repo:
```bash
cp ../ussdgateway/release-wildfly/wildfly-10.0.0.Final-cleaned.zip resources/
```

### Jolokia
The `build-all.sh` script auto-downloads jolokia-war 1.7.2 from Maven Central.

### Build
```bash
# Full build: clone + Maven + Ant + Docker
./build-all.sh

# Skip clone (already have local code)
SKIP_CLONE=1 ./build-all.sh

# Only build Docker image (already have zip)
SKIP_CLONE=1 SKIP_MAVEN=1 ./build-all.sh

# Build without creating Docker image
SKIP_DOCKER=1 ./build-all.sh
```

### Dependency build order
1. jain-slee (core SLEE framework)
2. jSS7 (SS7 protocol stack)
3. sip-servlets (SIP servlet)
4. jain-slee.ss7 (SS7/MAP RA)
5. jain-slee.sip (SIP RA)
6. jain-slee-http-okhttp (HTTP RA)
7. ussdgateway (USSD Gateway application)
8. Ant release → zip
9. Docker image (Zulu 8 JDK)

---

## Backup & Rollback

| Component | Command |
|-----------|---------|
| Backup host `/opt/ussdgw` | Automatic in `01-load`, `03-switch`, `02-setup` |
| List backups | `./scripts/02-setup-host.sh --list-backups` |
| Restore host | `sudo ./scripts/02-setup-host.sh --restore backups/ussdgw-*/` |
| Old image on disk | `docker images restcomm-ussd` |
| Rollback image | `./scripts/03-switch-gateway.sh --rollback` |
| Choose specific image | `./scripts/03-switch-gateway.sh --to <tag>` |

---

## Detailed Guides

| File | Content |
|------|---------|
| `docs/e2e-grpc-ussd-test.md` | E2E guide (VI) |
| `docs/e2e-grpc-ussd-test_en.md` | E2E guide (EN) |
| `docs/DEPLOY-GUIDE.md` | Deploy Docker image (end user) |
| `docs/BUILD-FROM-SOURCE.md` | **Build Docker image from source code (developer)** |
| `tools/jss7-map-load/USSD-LOADTEST.md` | MAP load CLI — package uses `lib/*` |

Run `./scripts/00-preflight.sh` before testing — verifies `map-load.jar`, Woodstox, docker tar.

---

## Ports

| Port | Service |
|------|---------|
| 8012 | SCTP Gateway |
| 8011 | MAP client |
| 8443 | gRPC AS |
| 8453 | gRPC Push (NI) |
| 8049 | HTTP Pull AS |
| 8080 | HTTP + Jolokia health (`/jolokia/version`) |
| 9090 | **BPF collector metrics** (`/metrics`, `/healthz`) |
| 9990 | WildFly management API |

---

## 📊 BPF/M3UA TPS Monitor + Live TUI Dashboard (new)

The entire stack runs via a **single `docker-compose.yml`** at the package root
(`docker-compose.yml`) comprising 4 services: `init`, `ussdgw`, `collector`, `tui`.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Master compose (docker-compose.yml)                                │
│                                                                     │
│  init (alpine, one-shot) → seed /opt/ussdgw                         │
│           ↓                                                         │
│  ussdgw (network_mode: host, Zulu 8 JDK, Wildfly 10)          │
│           │                                                         │
│  collector (Rust, AF_PACKET SCTP/M3UA, host net, NET_RAW)          │
│           ↓  HTTP /metrics @ :9090                                  │
│  tui (Rust ratatui/crossterm, host net, TTY-attached)              │
└─────────────────────────────────────────────────────────────────────┘
```

**TUI automatically appears on console** when you run:

```bash
# Method 1 — full stack foreground, TUI auto-attach at terminal end:
docker compose -f docker-compose.yml up

# Method 2 — gateway + collector daemon, TUI foreground:
docker compose -f docker-compose.yml up -d ussdgw collector
docker compose -f docker-compose.yml up tui

# Method 3 — use scripts:
./scripts/03-start-gateway.sh --with-monitor
./scripts/03-start-gateway.sh --tui-only       # attach TUI
```

Dashboard **renders in-place, does NOT scroll lines** because it uses
crossterm alternate-screen + ratatui dirty-cell redraw.

While TUI is running:
- `q` / `Esc` — quit
- `p` — pause/resume polling
- `r` — reset history (60s sparkline)

Detach from TUI without killing container: `Ctrl-p Ctrl-q`
Re-attach: `docker attach sctp-m3ua-tui`

See details in `bpf-tps-monitor/README.md` (collector `/metrics` JSON schema,
2-container explanation, `NET_RAW` requirement).

---

## 🏷️ Versioning

Package uses **Hybrid SemVer + CalVer** scheme: `<USSDGW_VERSION>+<BUILD_DATE>`

| Field | Example | Purpose |
|---|---|---|
| `USSDGW_VERSION` | `7.3.1` | SemVer core — stable, customer-facing, bumped on feature/fix |
| `BUILD_DATE` | `20260628` | CalVer — build date (UTC) |
| `BUILD_ID` | `20260628T052817-3d3881a` | Full audit id (date + time + git short hash) |
| `USSDGW_VERSION_FULL` | `7.3.1+20260628` | Combined (SemVer+CalVer) for log/banner |

**Download Docker image (not in git — too large ~700 MB):**

```bash
# From artifact server:
wget https://artifacts.digicom-et.com/ussdgw/docker/restcomm-ussd-zulu-7.3.1.tar -P docker/

# Or build from source:
cd ../ussdgateway/release-wildfly && ./build-docker-zulu.sh
```

**SemVer rules:**
- `PATCH` (7.3.1 → 7.3.2): bugfix, does not touch config/API
- `MINOR` (7.3.x → 7.4.0): new backward-compatible feature (add endpoint, add short code)
- `MAJOR` (7.x → 8.0.0): breaking change (drop Wildfly, change port, change /opt/ussdgw structure)

**Customer-facing Docker tag uses SemVer** (`restcomm-ussd-zulu:7.3.1`) — stable across multiple rebuilds.
**Internal release-specific tag** uses the full version (`restcomm-ussd-zulu:7.3.1-20260628-3d3881a`) — for rollback and audit.

Check current version:
```bash
./scripts/version.sh              # one-line
./scripts/version.sh --json       # machine-readable
./scripts/version.sh --all        # verbose
```

Override before build:
```bash
USSDGW_VERSION=7.4.0 ./scripts/build-package.sh
echo "7.4.0" > VERSION              # or edit VERSION file
```

---

## Package Structure

```
ussdgw-prod-release/
├── backups/              # ussdgw-host.tgz (created when running 01/02/03)
├── docker/               # image tar + package.manifest
├── gateway/              # compose + .env + config-seed + configuration/
├── tools/
├── docs/
└── scripts/
```

Host persistence (compose volumes):

| Host path | Container | Purpose |
|-----------|-----------|---------|
| `/opt/ussdgw/data` | SS7/USSD XML | Stack + routing config |
| `/opt/ussdgw/log` | WildFly logs | server.log |
| `/opt/ussdgw/configuration` | `standalone/configuration` | GUI auth (`mgmt-users.properties`) |

Creating a new package (on build machine):

```bash
cd ussdgateway/release-wildfly && ./build-docker.sh
docker context use default   # same context when loading/deploying
cd ../../ussdgw-prod-release && ./scripts/build-package.sh
tar czf ussdgw-prod-release-7.3.1.tar.gz -C .. ussdgw-prod-release
```

After `build-package.sh`, check `docker/package.manifest` (BUILD_ID) and `./scripts/00-preflight.sh`.

---

## Server Requirements

Docker, JDK 8, Python 3.9+, SCTP (`lsmod | grep sctp`), RAM ≥ 6 GB.
BPF collector/TUI additionally needs `NET_RAW` capability (already included in compose).

