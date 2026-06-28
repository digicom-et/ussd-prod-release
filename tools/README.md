# Test tools (bundled in ussdgw-prod-release)

Package luôn gồm 4 bộ công cụ — được copy tự động bởi `scripts/build-package.sh`.

| Directory | Source (dev) | Purpose |
|-----------|--------------|---------|
| `jss7-map-load/` | `jSS7/map/load` | MAP USSD load client |
| `jss7-simulator/` | `jSS7/tools/simulator` | SS7 simulator GUI |
| `grpc-as-tester/` | `ussdgateway/tools/grpc-as-tester` | Python gRPC AS + load client |
| `http-simulator/` | `ussdgateway/tools/http-simulator` | HTTP GUI + Python loadtest (pull/push) |

## Classpath (package layout)

Trong package, dependencies nằm ở `lib/` — **không** dùng `target/load/*` (chỉ path dev workspace).

### MAP load client

```bash
cd tools/jss7-map-load
java -cp "lib/*" org.restcomm.protocols.ss7.map.load.ussd.Client \
  10 5 sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP 101 102 1 2 3 2 8 6 8 \
  1111112 9960639999 1 4 -100 0 "*100#" BALANCE 50 200
```

### SS7 simulator GUI

```bash
cd tools/jss7-simulator
./bin/run.sh gui --name=main
```

Classpath: `lib/*` (được set trong `bin/run.sh`).

## Python venv (gRPC AS + HTTP loadtest)

Smoke/start scripts tạo `.venv` tự động khi chạy `05-start-grpc-as.sh` / `09-start-http-as.sh`. Để cài thủ công:

```bash
# gRPC AS + loadtest_client.py
cd tools/grpc-as-tester
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt

# HTTP push loadtest
cd tools/http-simulator/loadtest
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
```

## TPS warmup (default ON)

Tất cả load generator ramp TPS trong **60 giây** đầu trước khi đạt target. Steps: `1 → 100 → 500 → 1000 → 2000 → 3000 → 5000 → 7000 → 10000` (capped tại `--tps` / `MAXCONCURRENTDIALOGS`).

| Tool | Disable warmup |
|------|----------------|
| gRPC `loadtest_client.py` | `--no-warmup` |
| HTTP `http_push_loadtest.py` | `--no-warmup` |
| MAP `Client.java` | `-Dwarmup=false` |

## Smoke tests (từ thư mục gốc package)

```bash
./scripts/06-run-map-smoke.sh    # SS7 → Gateway → gRPC
./scripts/07-run-grpc-smoke.sh   # gRPC only
./scripts/00-preflight.sh        # verify JARs + woodstox + Client class
```

Chi tiết MAP load: `jss7-map-load/USSD-LOADTEST.md`
