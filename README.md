# USSD Gateway — Gói prod release

Giải nén → chạy script → verify. **Không cần build.**

---

## Chạy nhanh (copy-paste từng bước)

### Bước 1 — Giải nén và vào thư mục

```bash
cd /opt
tar xzf ussdgw-prod-release-7.3.0-SNAPSHOT.tar.gz
cd ussdgw-prod-release
```

### Bước 2 — SCTP + kiểm tra

```bash
lsmod | grep sctp          # phải thấy dòng sctp
# nếu trống:
sudo modprobe sctp

chmod +x scripts/*.sh
./scripts/00-preflight.sh
```

### Bước 3 — Load image Docker (backup host, không dừng GW)

```bash
./scripts/01-load-docker-image.sh
```

→ Backup `/opt/ussdgw` (nếu có) vào `backups/`, load tar, **giữ image cũ** để rollback.

### Bước 3b — Switch (nâng cấp) hoặc bỏ qua nếu cài mới

```bash
./scripts/03-switch-gateway.sh
```

### Bước 3c — Rollback (nếu bản mới lỗi)

```bash
./scripts/03-switch-gateway.sh --rollback
sudo ./scripts/02-setup-host.sh --restore backups/ussdgw-<timestamp>/
```

### Bước 4 — Setup host

```bash
sudo ./scripts/02-setup-host.sh
```

### Bước 5 — Start USSD Gateway (`docker compose up`) ⭐

```bash
./scripts/03-start-gateway.sh                # gateway only
./scripts/03-start-gateway.sh --with-monitor # gateway + BPF collector headless
curl -fs http://localhost:8080/jolokia/version && echo " OK"
```

Hoặc dùng master compose trực tiếp:

```bash
cd ussdgw-prod-release          # đứng tại package root
docker compose -f docker-compose.yml up -d ussdgw
docker compose -f docker-compose.yml up -d collector   # optional — BPF TPS monitor
```

### Bước 6–9

Xem `docs/e2e-grpc-ussd-test.md` — mỗi bước có **script** và **「Thay thế thủ công」** (lệnh từng công cụ).

| Bước | Script nhanh | Tool thủ công |
|------|--------------|---------------|
| 6 gRPC AS | `05-start-grpc-as.sh` | `ussd_as_server.py :8443` |
| 7 MAP smoke | `06-run-map-smoke.sh` | `java ... Client ... "*100#" BALANCE` |
| 8 gRPC load | `07-run-grpc-smoke.sh` | `loadtest_client.py` |
| 8b gRPC Push | `14-run-grpc-push-smoke.sh` | `grpc_push_client.py :8453` |
| 9 Dừng | `stop-all.sh` | `compose down` + kill AS PID |

Gộp cài mới: `sudo ./scripts/start-all.sh`

Bảng lệnh đầy đủ: [Phụ lục A](docs/e2e-grpc-ussd-test.md#phụ-lục-a--chạy-thủ-công-từng-công-cụ-thay-thế-script).

---

## Backup & rollback

| Thành phần | Lệnh |
|------------|------|
| Backup host `/opt/ussdgw` | Tự động trong `01-load`, `03-switch`, `02-setup` |
| Liệt kê backup | `./scripts/02-setup-host.sh --list-backups` |
| Restore host | `sudo ./scripts/02-setup-host.sh --restore backups/ussdgw-*/` |
| Image cũ trên disk | `docker images restcomm-ussd` |
| Rollback image | `./scripts/03-switch-gateway.sh --rollback` |
| Chọn image cụ thể | `./scripts/03-switch-gateway.sh --to <tag>` |

---

## Hướng dẫn chi tiết

| File | Nội dung |
|------|----------|
| `docs/e2e-grpc-ussd-test.md` | Hướng dẫn E2E (VI) |
| `docs/e2e-grpc-ussd-test_en.md` | E2E guide (EN) |
| `docs/DEPLOY-GUIDE.md` | Deploy Docker image (người dùng cuối) |
| `docs/BUILD-FROM-SOURCE.md` | **Build Docker image từ source code (developer)** |
| `tools/jss7-map-load/USSD-LOADTEST.md` | MAP load CLI — package dùng `lib/*` |

Chạy `./scripts/00-preflight.sh` trước test — verify `map-load.jar`, Woodstox, docker tar.

---

## Cấu trúc package

```
ussdgw-prod-release/
├── backups/              # ussdgw-host.tgz (tạo khi chạy 01/02/03)
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

Tạo package mới (máy build):

```bash
cd ussdgateway/release-wildfly && ./build-docker.sh
docker context use default   # cùng context khi load/deploy
cd ../../ussdgw-prod-release && ./scripts/build-package.sh
tar czf ussdgw-prod-release-7.3.0-SNAPSHOT.tar.gz -C .. ussdgw-prod-release
```

Sau `build-package.sh`, kiểm tra `docker/package.manifest` (BUILD_ID) và `./scripts/00-preflight.sh`.

## Ports

| Port | Dịch vụ |
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

## 📊 BPF/M3UA TPS Monitor + Live TUI Dashboard (mới)

Toàn bộ stack chạy qua **một `docker-compose.yml` duy nhất** ở package root
(`docker-compose.yml`) gồm 4 service: `init`, `ussdgw`, `collector`, `tui`.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Master compose (docker-compose.yml)                                │
│                                                                     │
│  init (alpine, one-shot) → seed /opt/ussdgw                         │
│           ↓                                                         │
│  ussdgw (network_mode: host, alpine+openjdk8, Wildfly 10)          │
│           │                                                         │
│  collector (Rust, AF_PACKET SCTP/M3UA, host net, NET_RAW)          │
│           ↓  HTTP /metrics @ :9090                                  │
│  tui (Rust ratatui/crossterm, host net, TTY-attached)              │
└─────────────────────────────────────────────────────────────────────┘
```

**TUI tự động hiện lên console** khi bạn chạy:

```bash
# Cách 1 — toàn bộ stack foreground, TUI auto-attach cuối terminal:
docker compose -f docker-compose.yml up

# Cách 2 — gateway + collector daemon, TUI foreground:
docker compose -f docker-compose.yml up -d ussdgw collector
docker compose -f docker-compose.yml up tui

# Cách 3 — dùng script:
./scripts/03-start-gateway.sh --with-monitor
./scripts/03-start-gateway.sh --tui-only       # attach TUI
```

Dashboard **render trong chỗ (in-place), KHÔNG cuộn dòng** vì dùng
crossterm alternate-screen + ratatui dirty-cell redraw.

Trong khi TUI đang chạy:
- `q` / `Esc` — thoát
- `p` — pause/resume polling
- `r` — reset history (60s sparkline)

Tách khỏi TUI mà không giết container: `Ctrl-p Ctrl-q`
Attach lại: `docker attach sctp-m3ua-tui`

Xem chi tiết ở `bpf-tps-monitor/README.md` (collector `/metrics` JSON schema,
giải thích 2 container, yêu cầu `NET_RAW`).

---

## Yêu cầu server

Docker, JDK 8, Python 3.9+, SCTP (`lsmod | grep sctp`), RAM ≥ 6 GB.
BPF collector/TUI cần thêm `NET_RAW` capability (đã có sẵn trong compose).
