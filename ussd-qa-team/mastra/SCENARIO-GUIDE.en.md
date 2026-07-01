# USSD Gateway — E2E Scenario Test Guide

**Version:** 1.0  
**Audience:** QA Engineers, DevOps, Integration Testers  
**Scope:** 11 scenarios (S0–S10) covering preflight checks, Docker deployment, host setup, gateway startup, and all four protocol paths (MAP/gRPC/HTTP Pull/HTTP Push) plus clean shutdown.

---

## Table of Contents

1. [Architecture Diagram](#architecture-diagram)
2. [Quick Reference Table](#quick-reference-table)
3. [How to Run All Scenarios](#how-to-run-all-scenarios)
4. [Viewing Live Logs & Tmux](#viewing-live-logs--tmux)
5. [PCAP Capture During Tests](#pcap-capture-during-tests)
6. [Step‑by‑Step Scenarios](#step-by-step-scenarios)
   - [S0 — Preflight](#s0--preflight)
   - [S1 — Load Docker Image](#s1--load-docker-image)
   - [S2 — Setup Host](#s2--setup-host)
   - [S3 — Start Gateway](#s3--start-gateway)
   - [S4 — Start gRPC AS](#s4--start-grpc-as)
   - [S5 — MAP Smoke](#s5--map-smoke)
   - [S6 — gRPC Smoke](#s6--grpc-smoke)
   - [S7 — gRPC Push Smoke](#s7--grpc-push-smoke)
   - [S8 — HTTP Pull](#s8--http-pull)
   - [S9 — HTTP Push](#s9--http-push)
   - [S10 — Stop All](#s10--stop-all)
7. [Troubleshooting Index](#troubleshooting-index)

---

## Architecture Diagram

```
┌──────────────┐     SCTP *100#     ┌──────────────┐     gRPC      ┌──────────────┐
│  MAP Client  │ ────────────────── │ USSD Gateway │ ──────────── │  gRPC AS     │
│  :8011       │                    │  :8012:8080  │              │  :8443       │
│  (Java)      │                    │  (Docker)    │              │  (Python)    │
└──────────────┘                    └──────┬───────┘              └──────────────┘
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                    ┌─────▼─────┐  ┌──────▼──────┐  ┌─────▼─────┐
                    │ HTTP AS   │  │ BPF Monitor │  │  Mastra   │
                    │ :8049     │  │ :9090       │  │  :4111    │
                    │ (Python)  │  │ (Rust)      │  │  (AI QA)  │
                    └───────────┘  └─────────────┘  └───────────┘
```

**Protocol flow summary:**

| Path         | Ingress        | Egress         | Test Scenario |
|-------------|----------------|----------------|---------------|
| MAP → gRPC  | SCTP :8011/12  | gRPC :8443     | S5            |
| gRPC direct | —              | gRPC :8443     | S6            |
| gRPC Push   | gRPC :8453     | Gateway → UE   | S7            |
| HTTP Pull   | SCTP + HTTP    | HTTP :8049     | S8            |
| HTTP Push   | HTTP :8080     | Gateway → UE   | S9            |

---

## Quick Reference Table

| #   | Name            | Tmux Window          | Log File(s)                                           | Duration   | Depends On |
|-----|-----------------|----------------------|-------------------------------------------------------|------------|------------|
| S0  | Preflight       | *(synchronous)*      | —                                                     | ~10 s      | —          |
| S1  | Load Docker     | *(synchronous)*      | —                                                     | 30 s – 2 m | S0         |
| S2  | Setup Host      | *(synchronous)*      | —                                                     | ~5 s       | S1         |
| S3  | Start Gateway   | `docker-gw`          | `/tmp/ussd-logs/docker-gw.log`                        | 3 – 5 m    | S2         |
| S4  | Start gRPC AS   | `grpc-as`            | `/tmp/ussd-logs/grpc-as.log`                          | ~10 s      | S3         |
| S5  | MAP Smoke       | `map-smoke`          | `/tmp/ussd-logs/map-smoke.log`                        | 30 s – 2 m | S3 + S4    |
| S6  | gRPC Smoke      | `grpc-smoke`         | `/tmp/ussd-logs/grpc-smoke.log`                       | ~40 s      | S4         |
| S7  | gRPC Push       | `grpc-push`          | `/tmp/ussd-logs/grpc-push.log`                        | ~40 s      | S3         |
| S8  | HTTP Pull       | `http-as` + `http-pull` | `/tmp/ussd-logs/http-as.log`, `/tmp/ussd-logs/http-pull.log` | 1 – 2 m | S3     |
| S9  | HTTP Push       | `http-push`          | `/tmp/ussd-logs/http-push.log`                        | ~40 s      | S3         |
| S10 | Stop All        | *(synchronous)*      | —                                                     | ~10 s      | —          |

---

## How to Run All Scenarios

### Option A — Via Mastra (recommended)

```bash
cd /opt/ussdgw-prod-release/ussd-qa-team/mastra

# Start Mastra dev server
npx mastra dev

# → Open http://localhost:4111 in your browser
# → Navigate to Workflows → scenario-runner → Start

# Or trigger via curl:
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S0","S1","S2","S3","S4","S5"], "pcap": true}}'
```

**Mastra payload reference:**

```json
{
  "scenarios": ["S0","S1","S2","S3","S4","S5","S6","S7","S8","S9","S10"],
  "pcap": true
}
```

- `scenarios` — ordered list of scenario IDs to execute.
- `pcap` — if `true`, Mastra launches `tcpdump` before S5 and stops it after S9.

### Option B — Via Individual Shell Scripts

```bash
export PKG_ROOT=/opt/ussdgw-prod-release

# Preflight (S0)
lsmod | grep sctp && java -version && python3 --version && docker info

# Load Docker image (S1)
cd $PKG_ROOT && bash scripts/01-load-docker-image.sh

# Setup host (S2)
sudo bash $PKG_ROOT/scripts/02-setup-host.sh

# Start gateway + optional BPF monitor (S3)
$PKG_ROOT/scripts/03-start-gateway.sh --with-monitor

# Start gRPC AS (S4)
$PKG_ROOT/scripts/05-start-grpc-as.sh

# MAP Smoke (S5)
$PKG_ROOT/scripts/06-run-map-smoke.sh

# gRPC Smoke (S6)
$PKG_ROOT/scripts/07-run-grpc-smoke.sh

# Stop everything (S10)
$PKG_ROOT/scripts/stop-all.sh
```

---

## Viewing Live Logs & Tmux

The test harness creates a tmux session named **`ussd-e2e-test`** with one window per running service:

```bash
# Attach to the tmux session
tmux attach -t ussd-e2e-test

# Inside tmux:
#   Ctrl-b 0-9  → switch between windows (docker-gw, grpc-as, map-smoke, …)
#   Ctrl-b d    → detach (leave everything running)
#   Ctrl-b [    → scroll mode (arrows / PgUp / PgDn; q to quit)

# List all windows in the session
tmux list-windows -t ussd-e2e-test
```

**Tail individual logs without tmux:**

```bash
tail -f /tmp/ussd-logs/docker-gw.log
tail -f /tmp/ussd-logs/map-smoke.log
tail -f /tmp/ussd-logs/grpc-smoke.log
tail -f /tmp/ussd-logs/http-as.log
tail -f /tmp/ussd-logs/http-pull.log
tail -f /tmp/ussd-logs/http-push.log
tail -f /tmp/ussd-logs/grpc-push.log
```

**Watch all logs at once (multitail):**

```bash
# Install if missing: sudo apt install multitail
multitail /tmp/ussd-logs/*.log
```

---

## PCAP Capture During Tests

Capture SCTP (proto 132) and gRPC (TCP port 8443) traffic for offline analysis:

```bash
# Start capture before running S5 (MAP Smoke):
sudo tcpdump -i any -s 0 -w /tmp/ussd-e2e.pcap \
  '(proto 132) or (tcp port 8443) or (tcp port 8453) or (tcp port 8049)' &

# Or, if Mastra is managing the capture (pcap: true), the file is written to:
# /tmp/ussd-logs/ussd-e2e.pcap

# Stop capture:
sudo pkill tcpdump

# Inspect the capture:
capinfos /tmp/ussd-e2e.pcap
wireshark /tmp/ussd-e2e.pcap &
```

**SCTP‑specific Wireshark filters:**

```
sctp.verification_tag           → find association start
m3ua.protocol_data.opcode == 1  → MAP messages
sccp.message_type == 0x09       → UDT (connectionless SCCP)
```

---

## Step‑by‑Step Scenarios

### S0 — Preflight

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Verify that all environment prerequisites are met before any deployment step. |
| **Dependencies**| None (first step). |
| **Duration**    | ~10 seconds. |
| **Tmux Window** | *(synchronous — does not use tmux)* |
| **Log File**    | stdout only (no persistent log). |

**Manual Command (copy‑paste ready):**

```bash
echo "=== S0: Preflight ===" \
  && echo -n "SCTP module:   " && (lsmod | grep sctp > /dev/null && echo "PASS" || echo "FAIL (missing)") \
  && echo -n "Java runtime:  " && (java -version 2>&1 | head -1) \
  && echo -n "Python3:       " && python3 --version \
  && echo -n "Docker daemon: " && (docker info > /dev/null 2>&1 && echo "PASS" || echo "FAIL (not running)") \
  && echo "=== Preflight complete ==="
```

**Mastra Command:**

```json
{"scenarios": ["S0"]}
```

**Expected Output:**

```
=== S0: Preflight ===
SCTP module:   PASS
Java runtime:  openjdk version "11.0.x" ...
Python3:       Python 3.x.x
Docker daemon: PASS
=== Preflight complete ===
```

**Health Check:** All four lines show `PASS` or a valid version string. Any `FAIL` blocks further execution.

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SCTP module: FAIL` | sctp kernel module not loaded | `sudo modprobe sctp` |
| `Java runtime:` error | No JRE/JDK or wrong version | `sudo apt install openjdk-11-jre-headless` |
| `Docker daemon: FAIL` | Docker not running | `sudo systemctl start docker` |
| `python3: not found` | Python 3 not installed | `sudo apt install python3` |

---

### S1 — Load Docker Image

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Import the RestComm USSD Gateway Docker image from the release tarball. |
| **Dependencies**| S0 must pass (Docker running). |
| **Duration**    | 30 seconds – 2 minutes (depends on `.tar` size, typically ~700 MB). |
| **Tmux Window** | *(synchronous)* |
| **Log File**    | stdout only. |

**Manual Command:**

```bash
cd /opt/ussdgw-prod-release && bash scripts/01-load-docker-image.sh
```

**Mastra Command:**

```json
{"scenarios": ["S1"]}
```

**Expected Output:** The script runs `docker load -i docker/restcomm-ussd-*.tar` and prints image metadata. No error messages on stderr.

**Health Check:**

```bash
docker images restcomm-ussd --format "{{.Repository}}:{{.Tag}}"
# Expected: restcomm-ussd:7.3.x (or similar version tag)
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No such file: docker/restcomm-ussd-*.tar` | Missing tarball | Verify `docker/` directory under `PKG_ROOT` |
| `Cannot connect to Docker daemon` | Docker not running | `sudo systemctl start docker` |
| `no space left on device` | Disk full | `df -h /var/lib/docker` |
| `Error: image already exists` | Prior import | Safe to ignore; image is cached |

---

### S2 — Setup Host

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Create `/opt/ussdgw` directory tree and seed default configuration (routing rules, SCTP associations). |
| **Dependencies**| S1 complete. |
| **Duration**    | ~5 seconds. |
| **Tmux Window** | *(synchronous)* |
| **Log File**    | stdout only. |

**Manual Command:**

```bash
sudo bash /opt/ussdgw-prod-release/scripts/02-setup-host.sh
```

**Mastra Command:**

```json
{"scenarios": ["S2"]}
```

**Expected Output:** Script completes silently or prints a short confirmation. No errors.

**Health Check:**

```bash
ls -la /opt/ussdgw/data/UssdManagement_scroutingrule.xml
# Expected: file exists with a recent timestamp
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Permission denied` | Script needs root for `/opt/ussdgw` | Run with `sudo` |
| Directory already exists | Previous run left data | Safe; script is idempotent |
| `02-setup-host.sh: No such file` | `PKG_ROOT` incorrect | `export PKG_ROOT=/opt/ussdgw-prod-release` |

---

### S3 — Start Gateway

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Launch the USSD Gateway via Docker Compose and wait for WildFly to become healthy. |
| **Dependencies**| S2 (host setup with routing rules). |
| **Duration**    | 3 – 5 minutes (first startup — WildFly boot + SCTP stack init). |
| **Tmux Window** | `docker-gw` |
| **Log File**    | `/tmp/ussd-logs/docker-gw.log` |

**Manual Command (with tmux):**

```bash
# Ensure log directory exists
mkdir -p /tmp/ussd-logs

# Start gateway in dedicated tmux window
tmux new-session -d -s ussd-e2e-test -n docker-gw \
  "docker compose -f /opt/ussdgw-prod-release/gateway/docker-compose.yml up 2>&1 | tee /tmp/ussd-logs/docker-gw.log"
```

**Manual Command (without tmux — foreground):**

```bash
cd /opt/ussdgw-prod-release/gateway && docker compose up -d
```

**Mastra Command:**

```json
{"scenarios": ["S3"]}
```

**Expected Output:** Gateway container starts and WildFly boots completely. The log shows:
- `WildFly Full ... started in ...`
- `SCTP stack initialized`
- `Jolokia: Agent started`

**Health Check:**

```bash
# Jolokia endpoint — returns JSON with WildFly version
curl -fs http://localhost:8080/jolokia/version
# Expected: HTTP 200 + JSON like {"timestamp":...,"value":{"version":"..."},"status":200}
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| Port 8080 not responding after 5 min | WildFly still booting or crashed | Check logs: `docker logs ussd-prod` or `tail -100 /tmp/ussd-logs/docker-gw.log` |
| `Address already in use` port 8080/8011/8012 | Previous instance still running | `docker compose -f /opt/ussdgw-prod-release/gateway/docker-compose.yml down` |
| `modprobe: FATAL: Module sctp not found` | SCTP kernel module missing | `sudo modprobe sctp && lsmod \| grep sctp` |
| `No route to host` for SCTP peer | Firewall blocking SCTP | `sudo iptables -L -n \| grep 8011` |
| Docker compose not found | `docker-compose` vs `docker compose` | Try `docker-compose` (with hyphen) or upgrade Docker |

**Wait strategy:** Poll Jolokia every 10s for up to 5 minutes:

```bash
for i in $(seq 1 30); do
  curl -fs http://localhost:8080/jolokia/version > /dev/null 2>&1 && echo "Gateway ready!" && break
  echo "Waiting... ($i/30)"
  sleep 10
done
```

---

### S4 — Start gRPC AS

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Start the Python gRPC Application Server that handles USSD menu logic (BALANCE, ENQUIRY profiles). |
| **Dependencies**| S3 (gateway healthy — the AS is independent but tests S5 need both). |
| **Duration**    | ~10 seconds. |
| **Tmux Window** | `grpc-as` |
| **Log File**    | `/tmp/ussd-logs/grpc-as.log` |

**Manual Command:**

```bash
cd /opt/ussdgw-prod-release/tools/grpc-as-tester
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python ussd_as_server.py \
  --port 8443 \
  --min-delay 1 \
  --max-delay 100 \
  --menu-config menu_config.json \
  2>&1 | tee /tmp/ussd-logs/grpc-as.log
```

**With tmux (backgrounded):**

```bash
mkdir -p /tmp/ussd-logs
tmux new-window -t ussd-e2e-test -n grpc-as \
  "cd /opt/ussdgw-prod-release/tools/grpc-as-tester && .venv/bin/python ussd_as_server.py --port 8443 --min-delay 1 --max-delay 100 --menu-config menu_config.json 2>&1 | tee /tmp/ussd-logs/grpc-as.log"
```

**Mastra Command:**

```json
{"scenarios": ["S4"]}
```

**Expected Output:**

```
USSD gRPC AS listening on :8443
Loaded menu config: menu_config.json
Profiles: BALANCE, ENQUIRY, ...
```

**Health Check:**

```bash
grep "listening on :8443" /tmp/ussd-logs/grpc-as.log
# Must return a matching line.
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Address already in use` port 8443 | Previous instance still running | `pkill -f ussd_as_server.py` then retry |
| `No module named 'grpcio'` | venv not set up | `cd tools/grpc-as-tester && .venv/bin/pip install -r requirements.txt` |
| `menu_config.json: No such file` | Wrong working directory | Always `cd tools/grpc-as-tester` first |
| Python version < 3.8 | Old Python | `python3 --version`; install 3.9+ |

---

### S5 — MAP Smoke

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | End‑to‑end SS7 MAP USSD test: MAP client → SCTP → Gateway → gRPC AS → Gateway → MAP response. Validates the full MAP/gRPC pipeline with `*100#` short code and BALANCE profile. |
| **Dependencies**| S3 (gateway healthy) + S4 (gRPC AS listening on :8443). |
| **Duration**    | 30 seconds – 2 minutes (first run includes ~20s SCTP INIT handshake). |
| **Tmux Window** | `map-smoke` |
| **Log File**    | `/tmp/ussd-logs/map-smoke.log` |

**Manual Command (copy‑paste ready):**

```bash
cd /opt/ussdgw-prod-release/tools/jss7-map-load && \
java -cp "lib/*" \
  org.restcomm.protocols.ss7.map.load.ussd.Client \
  10 5 \
  sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP \
  101 102 1 2 3 2 \
  8 6 8 1111112 9960639999 \
  1 4 -100 0 \
  "*100#" BALANCE 50 200 \
  2>&1 | tee /tmp/ussd-logs/map-smoke.log
```

**Parameter breakdown:**

| Param | Meaning | Value |
|-------|---------|-------|
| `10` | Total dialogs (USSD sessions) | 10 |
| `5` | Concurrent threads | 5 |
| `sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP` | SCTP local/remote bind | Local:8011, Remote:8012, IPSP client mode |
| `101 102 1 2 3 2` | M3UA routing context + network params | Standard test values |
| `8 6 8 1111112 9960639999` | GT + MSISDN addressing | IMSI:1111112, MSISDN:9960639999 |
| `1 4 -100 0` | SCCP addressing + SSN | SSN=4 (HLR), GT translation |
| `"*100#" BALANCE 50 200` | USSD string + profile + delays | *100# short code, BALANCE menu |

**Mastra Command:**

```json
{"scenarios": ["S5"]}
```

**Expected Output (key lines):**

```
Starting association with peer: 127.0.0.1:8012
AS1 state changed to: ACTIVE
AS1 is now ACTIVE!
...
Total completed dialogs = 10
FailedScenario  = 0
```

**Health Check:**

```bash
# Verify ACTIVE state and zero failures
grep -E "AS1 is now ACTIVE" /tmp/ussd-logs/map-smoke.log
grep "Total completed dialogs" /tmp/ussd-logs/map-smoke.log
grep "FailedScenario" /tmp/ussd-logs/map-smoke.log
# "FailedScenario = 0" is required for a passing test
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AS1 not ACTIVE after 30s` | SCTP association not established | Verify SCTP module: `lsmod \| grep sctp`. Check gateway logs for SCTP errors. |
| `java.lang.ClassNotFoundException` | Missing jSS7 libraries in `lib/` | Run `mvn dependency:copy-dependencies` in tools/jss7-map-load |
| `Not valid short code: *100#` | Routing rule missing | Edit `/opt/ussdgw/data/UssdManagement_scroutingrule.xml`, add `*100#` → gRPC entry, restart S2 |
| `Connection refused: 127.0.0.1:8011` | Gateway not listening SCTP | Check docker-gw log for `SCTP stack initialized`. Gateway may still be booting. |
| `gRPC deadline exceeded` | gRPC AS not responding | Verify S4: `grep "listening on :8443" /tmp/ussd-logs/grpc-as.log` |
| `FailedScenario > 0` | Some dialogs failed | Check individual dialog errors in map-smoke.log for the specific failure reason |

**Success criteria:** All three hold true:
1. `AS1 is now ACTIVE!` appears in log
2. `Total completed dialogs = 10`
3. `FailedScenario = 0`

---

### S6 — gRPC Smoke

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Load‑test the gRPC Application Server directly (bypassing SS7/gateway). Validates the AS can sustain concurrent gRPC menu sessions. |
| **Dependencies**| S4 (gRPC AS running on :8443). Gateway is NOT required. |
| **Duration**    | ~40 seconds (30s test duration + startup). |
| **Tmux Window** | `grpc-smoke` |
| **Log File**    | `/tmp/ussd-logs/grpc-smoke.log` |

**Manual Command:**

```bash
cd /opt/ussdgw-prod-release/tools/grpc-as-tester && \
.venv/bin/python loadtest_client.py \
  --target localhost:8443 \
  --tps 50 \
  --duration 30 \
  --multi-menu \
  --profile BALANCE \
  --think-min 50 \
  --think-max 200 \
  --menu-config menu_config.json \
  2>&1 | tee /tmp/ussd-logs/grpc-smoke.log
```

**Mastra Command:**

```json
{"scenarios": ["S6"]}
```

**Expected Output (key lines):**

```
mode: multi-menu
profile: BALANCE
target: localhost:8443
target TPS: 50
duration: 30s
...
completed: 1500
errors: 0
achieved TPS: 50.1
```

**Health Check:**

```bash
grep -E "completed:" /tmp/ussd-logs/grpc-smoke.log
grep "errors: 0" /tmp/ussd-logs/grpc-smoke.log
# Both must match; errors must be 0
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection refused` | gRPC AS not running | Verify S4: `grep "listening on :8443" /tmp/ussd-logs/grpc-as.log` |
| `achieved TPS` much lower than 50 | System overload or high latency | Reduce `--tps` to 20 and retry; check CPU with `htop` |
| `errors > 0` | AS returned errors | Check grpc-smoke.log for specific gRPC status codes |
| `ModuleNotFoundError: grpc` | venv not active | `cd tools/grpc-as-tester && .venv/bin/pip install -r requirements.txt` |

---

### S7 — gRPC Push Smoke

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Validate the gRPC Network‑Initiated (NI) Push path: external client sends USSD push requests to the gateway's gRPC Push endpoint, which delivers them to simulated UEs. |
| **Dependencies**| S3 (gateway must be running with gRPC Push enabled on port 8453). |
| **Duration**    | ~40 seconds. |
| **Tmux Window** | `grpc-push` |
| **Log File**    | `/tmp/ussd-logs/grpc-push.log` |

**Prerequisite — Enable gRPC Push on the gateway web management console:**

1. Open `http://localhost:9990` in a browser (WildFly management console).
2. Navigate to **Server Settings** → **gRPC Push**.
3. Set **GrpcPushServerEnabled** = `true`.
4. Set **Port** = `8453`.
5. Click **Save** and confirm.

**Manual Command:**

```bash
cd /opt/ussdgw-prod-release/tools/grpc-as-tester && \
.venv/bin/python grpc_push_client.py \
  --target localhost:8453 \
  --mode multi \
  --profile BALANCE \
  --tps 50 \
  --duration 30 \
  --think-min 50 \
  --think-max 200 \
  --menu-config menu_config.json \
  2>&1 | tee /tmp/ussd-logs/grpc-push.log
```

**Mastra Command:**

```json
{"scenarios": ["S7"]}
```

**Expected Output (key lines):**

```
mode: multi
profile: BALANCE
target: localhost:8453
...
completed: >0
errors: 0
```

**Health Check:**

```bash
grep "completed:" /tmp/ussd-logs/grpc-push.log
grep "errors: 0" /tmp/ussd-logs/grpc-push.log
# Both must match
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Connection refused` port 8453 | gRPC Push not enabled | Enable in web mgmt at `http://localhost:9990` |
| HTTP 404 from gateway | Gateway version lacks gRPC Push support | Verify gateway build includes the gRPC Push module |
| `errors > 0` | Push delivery failures | Check grpc-push.log for error details; verify UE simulation state |

---

### S8 — HTTP Pull

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | E2E test via the HTTP Pull path: MAP client → SCTP → Gateway → HTTP AS → Gateway → MAP response. Uses `*519#` short code routed to an HTTP Pull Application Server. |
| **Dependencies**| S3 (gateway healthy). gRPC AS is NOT required but the HTTP AS must be running. |
| **Duration**    | 1 – 2 minutes. |
| **Tmux Windows**| `http-as` + `http-pull` |
| **Log Files**   | `/tmp/ussd-logs/http-as.log`, `/tmp/ussd-logs/http-pull.log` |

**This scenario requires TWO terminals** (or two tmux windows):

#### Terminal 1 — HTTP AS Server

```bash
cd /opt/ussdgw-prod-release/tools/http-simulator/loadtest
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python http_as_server.py \
  --port 8049 \
  --min-delay 1 \
  --max-delay 100 \
  --menu-config menu_config.json \
  2>&1 | tee /tmp/ussd-logs/http-as.log
```

#### Terminal 2 — MAP Test against HTTP Pull

```bash
cd /opt/ussdgw-prod-release/tools/jss7-map-load && \
java -cp "lib/*" \
  org.restcomm.protocols.ss7.map.load.ussd.Client \
  10 5 \
  sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP \
  101 102 1 2 3 2 \
  8 6 8 1111112 9960639999 \
  1 4 -100 0 \
  "*519#" BALANCE 50 200 \
  2>&1 | tee /tmp/ussd-logs/http-pull.log
```

**Mastra Command:**

```json
{"scenarios": ["S8"]}
```

**Expected Output:**

- **http-as.log:** `HTTP AS listening on :8049`, incoming HTTP requests from gateway.
- **http-pull.log:** `AS1 is now ACTIVE!`, `Total completed dialogs = 10`, `FailedScenario = 0`.

**Health Check:**

```bash
# HTTP AS running
grep "listening on :8049" /tmp/ussd-logs/http-as.log

# MAP test passed
grep "FailedScenario = 0" /tmp/ussd-logs/http-pull.log
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| HTTP AS `Address already in use` :8049 | Previous instance | `pkill -f http_as_server.py` |
| `*519#` not routing | Missing HTTP scrule entry | Add `*519#` → HTTP Pull in `UssdManagement_scroutingrule.xml` |
| Gateway returns HTTP 500 | HTTP AS not responding fast enough | Increase `--max-delay` or check AS logs |
| MAP `Connection refused` :8011 | Gateway not running SCTP | Verify S3 is healthy via Jolokia |

---

### S9 — HTTP Push

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Load‑test the HTTP Network‑Initiated Push endpoint: external client sends USSD push requests via HTTP to the gateway's REST API, which delivers them to simulated UEs. |
| **Dependencies**| S3 (gateway must be running, HTTP REST endpoint at :8080). |
| **Duration**    | ~40 seconds. |
| **Tmux Window** | `http-push` |
| **Log File**    | `/tmp/ussd-logs/http-push.log` |

**Manual Command:**

```bash
cd /opt/ussdgw-prod-release/tools/http-simulator/loadtest && \
.venv/bin/python http_push_loadtest.py \
  --target http://127.0.0.1:8080/restcomm \
  --mode multi \
  --profile BALANCE \
  --tps 50 \
  --duration 30 \
  --think-min 50 \
  --think-max 200 \
  --menu-config menu_config.json \
  2>&1 | tee /tmp/ussd-logs/http-push.log
```

**Mastra Command:**

```json
{"scenarios": ["S9"]}
```

**Expected Output (key lines):**

```
mode: multi
profile: BALANCE
target: http://127.0.0.1:8080/restcomm
target TPS: 50
duration: 30s
...
completed: >0
errors: 0
achieved TPS: ...
```

**Health Check:**

```bash
grep "completed:" /tmp/ussd-logs/http-push.log
grep "errors: 0" /tmp/ussd-logs/http-push.log
# Both must match
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| HTTP 404 or `Connection refused` | Gateway REST endpoint not up | Verify: `curl -fs http://localhost:8080/restcomm` |
| `Connection reset by peer` | Gateway rejecting load | Reduce `--tps` to 20 |
| `errors > 0` | Push delivery failures | Check gateway docker-gw.log for exceptions |

---

### S10 — Stop All

| Attribute       | Value |
|-----------------|-------|
| **Purpose**     | Gracefully shut down all running services, Docker containers, and the tmux session. |
| **Dependencies**| Any or all of S3–S9 may be running. |
| **Duration**    | ~10 seconds. |
| **Tmux Window** | *(synchronous — tmux session is killed)* |
| **Log File**    | — |

**Manual Command (copy‑paste ready):**

```bash
# Kill Python processes
pkill -f ussd_as_server.py
pkill -f http_as_server.py
pkill -f loadtest_client.py
pkill -f grpc_push_client.py
pkill -f http_push_loadtest.py

# Stop Docker containers
cd /opt/ussdgw-prod-release/gateway && docker compose down

# Kill tmux session (optional — Mastra leaves it open for inspection)
# tmux kill-session -t ussd-e2e-test

echo "All services stopped."
```

**Mastra Command:**

```json
{"scenarios": ["S10"]}
```

**Expected Output:** All Python processes terminated, `docker compose down` completes, tmux session killed (or left open for inspection if run manually without the tmux kill line).

**Health Check:**

```bash
# No gateway processes
docker ps --filter "name=ussd-prod" --format "{{.Names}}" | wc -l
# Expected: 0

# No Python test servers
pgrep -af "ussd_as_server\|http_as_server\|loadtest_client\|grpc_push_client\|http_push_loadtest"
# Expected: no output
```

**Troubleshooting:**

| Symptom | Cause | Fix |
|---------|-------|-----|
| Docker container won't stop | Container hung | `docker kill ussd-prod` then `docker compose down` |
| `pkill` doesn't match | Process name differs | `ps aux | grep -E "as_server\|loadtest"` to find exact name |
| Ports still bound after stop | Zombie processes | `sudo lsof -i :8443,8049,8011,8012,8080` and `kill -9 <PID>` |

**Note:** The tmux session `ussd-e2e-test` is intentionally left open after the Mastra workflow so you can inspect logs. Close it manually with:
```bash
tmux kill-session -t ussd-e2e-test
```

---

## Troubleshooting Index

Quick lookup for issues occurring across multiple scenarios:

| Category | Symptom | Check |
|----------|---------|-------|
| **SCTP** | Association never ACTIVE | `lsmod \| grep sctp`, `sudo modprobe sctp` |
| **Docker** | Container exits immediately | `docker logs ussd-prod` for stack trace |
| **Ports** | `Address already in use` | `sudo ss -tlnp \| grep -E "8011\|8012\|8080\|8443\|8453\|8049"` |
| **gRPC** | Deadline exceeded | AS server reachable? `nc -zv localhost 8443` |
| **Routing** | Short code not recognized | `cat /opt/ussdgw/data/UssdManagement_scroutingrule.xml \| grep "*100#"` |
| **Memory** | Java OOM in docker-gw.log | Increase Docker memory: `docker update --memory 4g ussd-prod` |
| **Disk** | Logs filling disk | `du -sh /tmp/ussd-logs/`, clean with `rm -rf /tmp/ussd-logs/*.log` |
| **Mastra** | Workflow hangs | Check Mastra logs: `journalctl -u mastra` or `~/.mastra/logs/` |
| **PCAP** | tcpdump not capturing SCTP | SCTP is proto 132, use `-i lo` for localhost SCTP |

---

## Version History

| Date       | Version | Changes |
|------------|---------|---------|
| 2025-01-15 | 1.0     | Initial release: 11 scenarios (S0–S10) covering Preflight, Docker deploy, Gateway startup, MAP/gRPC/HTTP Pull/HTTP Push, and shutdown. |

---

*Generated for the USSD Gateway E2E QA team. Maintained alongside the Mastra scenario-runner workflow.*
