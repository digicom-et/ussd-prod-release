# 📋 HƯỚNG DẪN SCENARIO — USSD Gateway E2E Testing

> **Ngôn ngữ:** Tiếng Việt  
> **Đường dẫn gốc:** `/opt/ussdgw-prod-release/ussd-qa-team/mastra`  
> **Phiên bản:** 1.0.0  
> **Ngày cập nhật:** 01/07/2025

---

## 📑 MỤC LỤC

1. [Sơ Đồ Kiến Trúc](#-sơ-đồ-kiến-trúc)
2. [Bảng Tham Khảo Nhanh](#-bảng-tham-khảo-nhanh)
3. [S0 — Kiểm Tra Môi Trường](#s0--kiểm-tra-môi-trường)
4. [S1 — Tải Docker Image](#s1--tải-docker-image)
5. [S2 — Thiết Lập Máy Chủ](#s2--thiết-lập-máy-chủ)
6. [S3 — Khởi Động Gateway](#s3--khởi-động-gateway)
7. [S4 — Khởi Động gRPC AS](#s4--khởi-động-grpc-as)
8. [S5 — MAP Smoke Test](#s5--map-smoke-test)
9. [S6 — gRPC Smoke Test](#s6--grpc-smoke-test)
10. [S7 — gRPC Push Test](#s7--grpc-push-test)
11. [S8 — HTTP Pull Test](#s8--http-pull-test)
12. [S9 — HTTP Push Test](#s9--http-push-test)
13. [S10 — Dừng Tất Cả](#s10--dừng-tất-cả)
14. [Cách Chạy Tất Cả Scenario](#-cách-chạy-tất-cả-scenario)
15. [Xem Log Trực Tiếp](#-xem-log-trực-tiếp)
16. [Bắt Gói Tin PCAP](#-bắt-gói-tin-pcap)
17. [Phụ Lục: Cấu Trúc Thư Mục](#-phụ-lục-cấu-trúc-thư-mục)

---

## 🏗️ SƠ ĐỒ KIẾN TRÚC

```
┌──────────────────┐   SCTP *100#    ┌──────────────────┐   gRPC     ┌──────────────────┐
│   MAP Client     │────────────────▶│  USSD Gateway    │──────────▶│   gRPC AS        │
│   :8011 (Java)   │                 │  :8012 (Docker)  │           │   :8443 (Python) │
└──────────────────┘                 └────────┬─────────┘           └──────────────────┘
                                              │
                       ┌──────────────────────┼──────────────────────┐
                       │                      │                      │
                 ┌─────▼─────┐        ┌──────▼──────┐        ┌──────▼──────┐
                 │  HTTP AS  │        │ BPF Monitor │        │   Mastra    │
                 │  :8049    │        │ :9090 (Rust)│        │   :4111     │
                 └───────────┘        └─────────────┘        └─────────────┘
```

### Cổng Dịch Vụ

| Cổng  | Dịch Vụ               | Giao Thức | Mô Tả                                    |
|-------|-----------------------|-----------|------------------------------------------|
| 8011  | MAP Client            | SCTP/MAP  | Client mô phỏng thiết bị di động         |
| 8012  | USSD Gateway (SCTP)   | SCTP/MAP  | Gateway nhận MAP request                 |
| 8080  | USSD Gateway (HTTP)   | HTTP      | REST API cho HTTP Push                   |
| 8443  | gRPC AS Server        | gRPC      | Application Server nhận gRPC từ Gateway  |
| 8049  | HTTP AS Server        | HTTP      | Application Server nhận HTTP Pull        |
| 8453  | gRPC Push Server      | gRPC      | Server nhận Push notification            |
| 9990  | Web Management        | HTTP      | Giao diện quản trị Gateway               |
| 9090  | BPF Monitor           | HTTP      | Giám sát hiệu năng kernel-level          |
| 4111  | Mastra Orchestrator   | HTTP      | Điều phối workflow E2E                   |

---

## 📊 BẢNG THAM KHẢO NHANH

| #   | Tên                  | Cửa Sổ Tmux        | File Log                           | Thời Gian   | Phụ Thuộc      |
|-----|----------------------|---------------------|------------------------------------|-------------|-----------------|
| S0  | Kiểm Tra Môi Trường  | *(đồng bộ)*         | —                                  | ~10 giây    | —               |
| S1  | Tải Docker Image     | *(đồng bộ)*         | —                                  | 30s – 2 phút| S0              |
| S2  | Thiết Lập Máy Chủ    | *(đồng bộ)*         | —                                  | ~5 giây     | S1              |
| S3  | Khởi Động Gateway    | `docker-gw`         | `/tmp/ussd-logs/docker-gw.log`     | 3 – 5 phút  | S2              |
| S4  | Khởi Động gRPC AS    | `grpc-as`           | `/tmp/ussd-logs/grpc-as.log`       | ~10 giây    | S3              |
| S5  | MAP Smoke Test       | `map-smoke`         | `/tmp/ussd-logs/map-smoke.log`     | 30s – 2 phút| S3 + S4         |
| S6  | gRPC Smoke Test      | `grpc-smoke`        | `/tmp/ussd-logs/grpc-smoke.log`    | ~40 giây    | S4              |
| S7  | gRPC Push Test       | `grpc-push`         | `/tmp/ussd-logs/grpc-push.log`     | ~40 giây    | S3              |
| S8  | HTTP Pull Test       | `http-as`, `http-pull`| `/tmp/ussd-logs/http-as.log`, `/tmp/ussd-logs/http-pull.log` | 1 – 2 phút | S3 |
| S9  | HTTP Push Test       | `http-push`         | `/tmp/ussd-logs/http-push.log`     | ~40 giây    | S3              |
| S10 | Dừng Tất Cả          | *(đồng bộ)*         | —                                  | ~10 giây    | —               |

---

## S0 — KIỂM TRA MÔI TRƯỜNG

### 1. Mục Đích

Xác minh rằng tất cả các thành phần hệ thống cần thiết đã được cài đặt và sẵn sàng trước khi bắt đầu bất kỳ scenario nào. Bước này kiểm tra kernel module SCTP, phiên bản Java, Python, Docker, và cấu trúc thư mục gốc.

### 2. Phụ Thuộc

Không có — đây là bước đầu tiên trong pipeline.

### 3. Lệnh Thủ Công

Sao chép và dán từng lệnh sau vào terminal:

```bash
# Kiểm tra module SCTP trong kernel
lsmod | grep sctp

# Kiểm tra phiên bản Java (yêu cầu Java 8/11/17)
java -version

# Kiểm tra phiên bản Python (yêu cầu ≥ 3.8)
python3 --version

# Kiểm tra Docker daemon đang chạy
docker info > /dev/null 2>&1 && echo "Docker OK" || echo "Docker FAIL"

# Kiểm tra thư mục gốc PKG_ROOT
test -d /opt/ussdgw-prod-release && echo "PKG_ROOT OK" || echo "PKG_ROOT FAIL"
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S0"]}}'
```

### 5. Cửa Sổ Tmux

Không áp dụng — chạy đồng bộ trực tiếp trên terminal chính.

### 6. File Log

Không có file log riêng. Kết quả được in ra stdout/stderr.

### 7. Kết Quả Mong Đợi

```
sctp                   77824  0
java version "11.0.22" 2024-01-16 LTS
Python 3.10.12
Docker OK
PKG_ROOT OK
```

- Module `sctp` phải xuất hiện trong danh sách `lsmod`.
- Java version hiển thị rõ ràng không có lỗi.
- Python version ≥ 3.8.
- Docker daemon phản hồi thành công.
- Thư mục `/opt/ussdgw-prod-release` tồn tại.

### 8. Kiểm Tra Sức Khỏe

```bash
# Xác nhận tất cả 5 lệnh trên đều trả về kết quả thành công
lsmod | grep -q sctp && echo "[PASS] SCTP" || echo "[FAIL] SCTP"
java -version 2>&1 | grep -q "version" && echo "[PASS] Java" || echo "[FAIL] Java"
python3 --version 2>&1 | grep -q "3\.[89]\|3\.1[0-9]" && echo "[PASS] Python" || echo "[FAIL] Python"
docker info > /dev/null 2>&1 && echo "[PASS] Docker" || echo "[FAIL] Docker"
test -d /opt/ussdgw-prod-release && echo "[PASS] PKG_ROOT" || echo "[FAIL] PKG_ROOT"
```

### 9. Xử Lý Sự Cố

| Lỗi                          | Nguyên Nhân                                   | Cách Khắc Phục                                      |
|------------------------------|-----------------------------------------------|-----------------------------------------------------|
| `lsmod` không có `sctp`      | Module SCTP chưa được nạp vào kernel          | `sudo modprobe sctp`                                |
| `java: command not found`    | Java chưa được cài đặt hoặc không có trong PATH| `sudo apt install openjdk-11-jdk`                   |
| `python3: command not found` | Python 3 chưa được cài đặt                    | `sudo apt install python3`                          |
| `Docker FAIL`                | Docker daemon chưa chạy hoặc quyền bị từ chối | `sudo systemctl start docker && sudo usermod -aG docker $USER` |
| `PKG_ROOT FAIL`              | Thư mục gốc không tồn tại                     | Kiểm tra lại đường dẫn giải nén bản release         |

### 10. Thời Gian

Khoảng **10 giây**.

---

## S1 — TẢI DOCKER IMAGE

### 1. Mục Đích

Nạp Docker image `restcomm-ussd` vào local Docker registry từ file `.tar.gz` có sẵn trong gói release. Image này chứa toàn bộ USSD Gateway runtime (Java + RestComm SLEE + cấu hình).

### 2. Phụ Thuộc

**S0** — Docker phải hoạt động, thư mục `PKG_ROOT` phải tồn tại.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release
bash scripts/01-load-docker-image.sh
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S1"]}}'
```

### 5. Cửa Sổ Tmux

Không áp dụng — chạy đồng bộ.

### 6. File Log

Không có file log riêng. Output xuất ra stdout.

### 7. Kết Quả Mong Đợi

```
Loading Docker image: restcomm-ussd:7.3.0 ...
Loaded image: restcomm-ussd:7.3.0
Image verified: restcomm-ussd  7.3.0  abc123def456  2 weeks ago  1.2GB
```

Xác nhận bằng lệnh:

```bash
docker images restcomm-ussd
```

Phải hiển thị tag `7.3.0` (hoặc tag release tương ứng).

### 8. Kiểm Tra Sức Khỏe

```bash
docker images restcomm-ussd --format "{{.Repository}}:{{.Tag}}" | grep -q "restcomm-ussd" && echo "[PASS] Image loaded" || echo "[FAIL] Image missing"
```

### 9. Xử Lý Sự Cố

| Lỗi                               | Nguyên Nhân                             | Cách Khắc Phục                                      |
|-----------------------------------|-----------------------------------------|-----------------------------------------------------|
| `Cannot connect to Docker daemon` | Docker daemon chưa chạy                 | `sudo systemctl start docker`                       |
| `No such file: *.tar.gz`          | File image không có trong thư mục gốc   | Kiểm tra `ls /opt/ussdgw-prod-release/docker/*.tar.gz` |
| `out of disk space`               | Ổ đĩa đầy                               | `df -h`, dọn dẹp image cũ: `docker system prune -a` |
| `Permission denied`               | User không có quyền truy cập Docker     | `sudo usermod -aG docker $USER`, sau đó đăng xuất/đăng nhập lại |

### 10. Thời Gian

Khoảng **30 giây đến 2 phút** (tùy tốc độ ổ đĩa I/O).

---

## S2 — THIẾT LẬP MÁY CHỦ

### 1. Mục Đích

Tạo cấu trúc thư mục `/opt/ussdgw/data`, copy các file cấu hình XML, thiết lập quyền truy cập, và chuẩn bị môi trường host cho Docker container.

### 2. Phụ Thuộc

**S1** — Docker image đã được nạp thành công.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release
sudo bash scripts/02-setup-host.sh
```

> ⚠️ **Yêu cầu `sudo`** vì script tạo thư mục trong `/opt` và thiết lập quyền hệ thống.

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S2"]}}'
```

### 5. Cửa Sổ Tmux

Không áp dụng — chạy đồng bộ.

### 6. File Log

Không có file log riêng.

### 7. Kết Quả Mong Đợi

```
Creating /opt/ussdgw/data ...
Creating /opt/ussdgw/data/config ...
Copying XML configuration files ...
Setting permissions ...
Host setup complete.
```

Xác nhận:

```bash
ls -la /opt/ussdgw/data/
ls -la /opt/ussdgw/data/*.xml
```

Phải thấy các file XML cấu hình (ví dụ: `ussd-gateway-config.xml`, `slee-config.xml`).

### 8. Kiểm Tra Sức Khỏe

```bash
test -f /opt/ussdgw/data/ussd-gateway-config.xml && echo "[PASS] Config exists" || echo "[FAIL] Config missing"
test -d /opt/ussdgw/data && echo "[PASS] Data dir exists" || echo "[FAIL] Data dir missing"
```

### 9. Xử Lý Sự Cố

| Lỗi                          | Nguyên Nhân                           | Cách Khắc Phục                                   |
|------------------------------|---------------------------------------|--------------------------------------------------|
| `Permission denied`          | Thiếu quyền sudo                      | Chạy lại với `sudo`                              |
| `mkdir: cannot create directory` | Thư mục cha không tồn tại         | `sudo mkdir -p /opt/ussdgw/data`                 |
| Thiếu file XML               | Gói release không đầy đủ              | Kiểm tra `ls /opt/ussdgw-prod-release/config/`   |

### 10. Thời Gian

Khoảng **5 giây**.

---

## S3 — KHỞI ĐỘNG GATEWAY

### 1. Mục Đích

Khởi động USSD Gateway Docker container (RestComm SLEE + jSS7 stack) và xác nhận rằng Gateway sẵn sàng phục vụ request qua cổng HTTP management.

### 2. Phụ Thuộc

**S2** — Cấu hình máy chủ đã được thiết lập.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release/gateway
docker compose up -d

# Đợi Gateway khởi động hoàn tất (lặp kiểm tra)
for i in $(seq 1 60); do
  curl -s http://localhost:8080/jolokia/version > /dev/null 2>&1 && break
  echo "Đợi Gateway... ($i/60)"
  sleep 5
done

# Xác nhận
curl -s http://localhost:8080/jolokia/version
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S3"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ:** `docker-gw`

```bash
tmux new-window -t ussd-e2e-test -n docker-gw
docker compose -f /opt/ussdgw-prod-release/gateway/docker-compose.yml logs -f
```

### 6. File Log

**Đường dẫn:** `/tmp/ussd-logs/docker-gw.log`

```bash
mkdir -p /tmp/ussd-logs
docker compose -f /opt/ussdgw-prod-release/gateway/docker-compose.yml logs -f > /tmp/ussd-logs/docker-gw.log 2>&1 &
```

### 7. Kết Quả Mong Đợi

Phản hồi từ Jolokia endpoint:

```json
{
  "timestamp": 1719876543,
  "status": 200,
  "request": {...},
  "value": {
    "protocol": "7.2",
    "agent": "1.7.2",
    "info": {}
  }
}
```

HTTP status code **200** — Gateway đã sẵn sàng.

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra HTTP endpoint
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/jolokia/version | grep -q "200" && echo "[PASS] Gateway HTTP OK" || echo "[FAIL] Gateway HTTP"

# Kiểm tra container đang chạy
docker ps --format "{{.Names}}: {{.Status}}" | grep -q "ussdgw" && echo "[PASS] Container running" || echo "[FAIL] Container down"

# Kiểm tra cổng SCTP đang lắng nghe
ss -tlnp | grep -q "8012" && echo "[PASS] SCTP port 8012 listening" || echo "[WARN] SCTP port not listening yet"
```

### 9. Xử Lý Sự Cố

| Lỗi                              | Nguyên Nhân                                    | Cách Khắc Phục                                      |
|----------------------------------|------------------------------------------------|-----------------------------------------------------|
| `curl: Connection refused`       | Gateway chưa khởi động xong                    | Đợi thêm 1-2 phút, kiểm tra `docker ps`            |
| Container liên tục restart       | Cấu hình XML lỗi hoặc thiếu file               | `docker logs ussdgw-gateway-1`, kiểm tra log lỗi   |
| `port already in use` trên 8012  | Cổng SCTP bị chiếm bởi tiến trình khác         | `sudo lsof -i :8012`, kill tiến trình cũ           |
| `out of memory`                  | Container bị giới hạn RAM                      | Tăng RAM trong `docker-compose.yml` hoặc `docker run --memory` |
| Gateway khởi động nhưng không có SCTP | Module SCTP kernel chưa nạp               | `sudo modprobe sctp`                                |

### 10. Thời Gian

Khoảng **3 – 5 phút** (lần đầu khởi động). Các lần sau nhanh hơn (~1 phút).

---

## S4 — KHỞI ĐỘNG gRPC AS

### 1. Mục Đích

Khởi động Application Server (AS) gRPC — một Python server lắng nghe trên cổng 8443, xử lý các request USSD được Gateway chuyển tiếp qua gRPC.

### 2. Phụ Thuộc

**S3** — Gateway phải đang chạy và sẵn sàng.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release
python3 ussd_as_server.py --port 8443
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S4"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ:** `grpc-as`

```bash
tmux new-window -t ussd-e2e-test -n grpc-as
python3 /opt/ussdgw-prod-release/ussd_as_server.py --port 8443
```

### 6. File Log

**Đường dẫn:** `/tmp/ussd-logs/grpc-as.log`

```bash
python3 /opt/ussdgw-prod-release/ussd_as_server.py --port 8443 > /tmp/ussd-logs/grpc-as.log 2>&1 &
```

### 7. Kết Quả Mong Đợi

```
INFO:root:USSD gRPC Application Server starting...
INFO:root:Loading gRPC service definitions...
INFO:root:Starting gRPC server on 0.0.0.0:8443
INFO:root:Server is now listening on :8443
```

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra cổng 8443 đang lắng nghe
ss -tlnp | grep -q "8443" && echo "[PASS] gRPC AS port 8443 listening" || echo "[FAIL] Port 8443 not listening"

# Kiểm tra tiến trình Python
pgrep -f "ussd_as_server.py" > /dev/null && echo "[PASS] Process running" || echo "[FAIL] Process not found"

# Kiểm tra log
grep -q "listening on :8443" /tmp/ussd-logs/grpc-as.log && echo "[PASS] Server confirmed" || echo "[WARN] Not confirmed"
```

### 9. Xử Lý Sự Cố

| Lỗi                              | Nguyên Nhân                              | Cách Khắc Phục                                      |
|----------------------------------|------------------------------------------|-----------------------------------------------------|
| `ModuleNotFoundError: grpc`      | Thư viện gRPC Python chưa được cài đặt   | `pip3 install grpcio grpcio-tools`                  |
| `Address already in use`         | Cổng 8443 bị chiếm                       | `sudo lsof -i :8443`, kill tiến trình cũ hoặc đổi cổng |
| `ImportError: ussd_pb2`          | File protobuf chưa được generate         | `python3 -m grpc_tools.protoc ...`                  |
| Python version quá cũ            | Python < 3.8                             | Cài đặt Python 3.10+                                |

### 10. Thời Gian

Khoảng **10 giây**.

---

## S5 — MAP SMOKE TEST

### 1. Mục Đích

Kiểm tra kết nối MAP/SCTP end-to-end bằng cách gửi 10 USSD request `*100# BALANCE` qua SCTP từ Java MAP Client đến Gateway, và xác nhận Gateway chuyển tiếp sang gRPC AS thành công.

### 2. Phụ Thuộc

**S3** + **S4** — Gateway và gRPC AS đều phải đang chạy.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release
java -cp "lib/*:." Client 10 "*100# BALANCE"
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S5"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ:** `map-smoke`

```bash
tmux new-window -t ussd-e2e-test -n map-smoke
java -cp "/opt/ussdgw-prod-release/lib/*:/opt/ussdgw-prod-release/." Client 10 "*100# BALANCE"
```

### 6. File Log

**Đường dẫn:** `/tmp/ussd-logs/map-smoke.log`

```bash
java -cp "/opt/ussdgw-prod-release/lib/*:/opt/ussdgw-prod-release/." Client 10 "*100# BALANCE" > /tmp/ussd-logs/map-smoke.log 2>&1
```

### 7. Kết Quả Mong Đợi

```
MAP Smoke Test — Starting 10 dialogs with USSD string: *100# BALANCE
[DIALOG 1] Sending MAP_UNSTRUCTURED_SS_REQUEST...
[DIALOG 1] Received TC_BEGIN + MAP_UNSTRUCTURED_SS_RESPONSE
[DIALOG 1] AS1 is now ACTIVE!
...
[DIALOG 10] AS1 is now ACTIVE!
========================================
Total completed dialogs = 10
Total failed dialogs = 0
Test PASSED
========================================
```

Dòng quan trọng nhất:
- `"AS1 is now ACTIVE!"` — Gateway đã kết nối và kích hoạt thành công gRPC AS.
- `"Total completed dialogs = 10"` — Tất cả 10 dialog MAP hoàn thành.

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra log có dialog thành công
grep -c "AS1 is now ACTIVE" /tmp/ussd-logs/map-smoke.log | xargs -I{} test {} -eq 10 && echo "[PASS] 10 dialogs active" || echo "[FAIL] Missing dialogs"

# Kiểm tra không có dialog lỗi
grep -c "failed" /tmp/ussd-logs/map-smoke.log | xargs -I{} test {} -eq 0 && echo "[PASS] Zero failures" || echo "[FAIL] Failures detected"
```

### 9. Xử Lý Sự Cố

| Lỗi                                   | Nguyên Nhân                                  | Cách Khắc Phục                                  |
|---------------------------------------|----------------------------------------------|-------------------------------------------------|
| `Connection refused: 8012`            | Gateway SCTP chưa sẵn sàng                   | Đợi Gateway khởi động hoàn tất, kiểm tra S3    |
| `No route to host`                    | Cấu hình mạng hoặc firewall chặn SCTP        | Kiểm tra `iptables`, đảm bảo loopback cho phép |
| `TC_ABORT` hoặc `TC_REJECT`           | Gateway từ chối dialog MAP                   | Kiểm tra log Gateway, verify cấu hình MAP      |
| `java.lang.ClassNotFoundException`    | Thiếu file JAR trong CLASSPATH               | Kiểm tra `ls /opt/ussdgw-prod-release/lib/`    |
| `0 completed dialogs`                 | gRPC AS không nhận được request              | Kiểm tra log `grpc-as.log`, verify S4 đang chạy |

### 10. Thời Gian

Khoảng **30 giây đến 2 phút**.

---

## S6 — gRPC SMOKE TEST

### 1. Mục Đích

Kiểm tra hiệu năng và độ ổn định của gRPC Application Server bằng cách gửi tải 50 TPS (transactions per second) trong 30 giây với multi-menu USSD scenario.

### 2. Phụ Thuộc

**S4** — gRPC AS phải đang chạy trên cổng 8443.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release
python3 loadtest_client.py --target :8443 --tps 50 --duration 30 --multi-menu
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S6"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ:** `grpc-smoke`

```bash
tmux new-window -t ussd-e2e-test -n grpc-smoke
python3 /opt/ussdgw-prod-release/loadtest_client.py --target :8443 --tps 50 --duration 30 --multi-menu
```

### 6. File Log

**Đường dẫn:** `/tmp/ussd-logs/grpc-smoke.log`

```bash
python3 /opt/ussdgw-prod-release/loadtest_client.py --target :8443 --tps 50 --duration 30 --multi-menu > /tmp/ussd-logs/grpc-smoke.log 2>&1
```

### 7. Kết Quả Mong Đợi

```
gRPC Load Test Client
Target: :8443
TPS: 50
Duration: 30 seconds
Mode: multi-menu
========================================
Starting load test...
[PROGRESS] 5s: 250 requests, errors: 0
[PROGRESS] 10s: 500 requests, errors: 0
[PROGRESS] 15s: 750 requests, errors: 0
[PROGRESS] 20s: 1000 requests, errors: 0
[PROGRESS] 25s: 1250 requests, errors: 0
[PROGRESS] 30s: 1500 requests, errors: 0
========================================
Load test complete.
Total requests: 1500
Total errors: 0
Achieved TPS: 50.0
Test PASSED
```

Hai chỉ số quan trọng:
- `"errors: 0"` — Không có lỗi nào trong suốt quá trình test.
- `"Achieved TPS: ..."` — TPS đạt được phải gần với mục tiêu 50.

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra không có lỗi
grep -q "errors: 0" /tmp/ussd-logs/grpc-smoke.log && echo "[PASS] Zero gRPC errors" || echo "[FAIL] gRPC errors detected"

# Kiểm tra TPS đạt được
grep "Achieved TPS" /tmp/ussd-logs/grpc-smoke.log | grep -oP '\d+\.\d+' | xargs -I{} sh -c 'echo "{} >= 45" | bc -l | grep -q 1' && echo "[PASS] TPS within range" || echo "[WARN] TPS below target"
```

### 9. Xử Lý Sự Cố

| Lỗi                              | Nguyên Nhân                                   | Cách Khắc Phục                               |
|----------------------------------|-----------------------------------------------|----------------------------------------------|
| `Connection refused`             | gRPC AS chưa khởi động                        | Chạy lại S4                                  |
| `Deadline exceeded`              | Timeout mạng hoặc AS xử lý quá chậm           | Tăng timeout, kiểm tra CPU/RAM server        |
| `errors > 0`                     | Một số request thất bại                       | Kiểm tra chi tiết log lỗi                    |
| TPS thực tế thấp hơn mục tiêu    | Giới hạn CPU hoặc mạng                        | Giảm TPS mục tiêu, kiểm tra tải hệ thống     |

### 10. Thời Gian

Khoảng **40 giây** (30 giây test + 10 giây khởi tạo/kết thúc).

---

## S7 — gRPC PUSH TEST

### 1. Mục Đích

Kiểm tra cơ chế gRPC Push — nơi Gateway chủ động gửi USSD notification đến một gRPC Push Server trên cổng 8453 (không cần client khởi tạo dialog). Yêu cầu bật gRPC Push trên Web Management.

### 2. Phụ Thuộc

**S3** — Gateway phải đang chạy. Cần bật gRPC Push qua Web Management trên cổng 9990.

### 3. Lệnh Thủ Công

**Bước 1: Bật gRPC Push trên Web Management**

```bash
# Mở trình duyệt hoặc dùng curl để bật gRPC Push
curl -X POST http://localhost:9990/management/grpc-push/enable \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "target": "localhost:8453"}'
```

**Bước 2: Khởi động gRPC Push Client**

```bash
cd /opt/ussdgw-prod-release
python3 grpc_push_client.py --target :8453 --mode multi
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S7"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ:** `grpc-push`

```bash
tmux new-window -t ussd-e2e-test -n grpc-push
# Trước tiên bật gRPC Push trên Web Management
curl -X POST http://localhost:9990/management/grpc-push/enable \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "target": "localhost:8453"}'

# Sau đó chạy push client
python3 /opt/ussdgw-prod-release/grpc_push_client.py --target :8453 --mode multi
```

### 6. File Log

**Đường dẫn:** `/tmp/ussd-logs/grpc-push.log`

```bash
python3 /opt/ussdgw-prod-release/grpc_push_client.py --target :8453 --mode multi > /tmp/ussd-logs/grpc-push.log 2>&1
```

### 7. Kết Quả Mong Đợi

```
gRPC Push Client
Target: :8453
Mode: multi
========================================
Subscribe gRPC Push Server started on :8453
Waiting for push notifications from Gateway...
[PUSH 1] Received USSD notification: session_id=abc123, msisdn=2519...
[PUSH 2] Received USSD notification: session_id=def456, msisdn=2519...
...
[PUSH 10] Received USSD notification: session_id=jkl012, msisdn=2519...
========================================
Total push notifications received: 10
Total errors: 0
Test PASSED
```

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra push notification được nhận
grep -c "Received USSD notification" /tmp/ussd-logs/grpc-push.log | xargs -I{} test {} -gt 0 && echo "[PASS] Push notifications received" || echo "[FAIL] No push notifications"

# Kiểm tra không có lỗi
grep -q "errors: 0" /tmp/ussd-logs/grpc-push.log && echo "[PASS] Zero errors" || echo "[FAIL] Errors detected"
```

### 9. Xử Lý Sự Cố

| Lỗi                                | Nguyên Nhân                                | Cách Khắc Phục                                    |
|------------------------------------|--------------------------------------------|---------------------------------------------------|
| Không nhận được push notification  | gRPC Push chưa được bật trên Web Management| Kiểm tra `curl http://localhost:9990/management/grpc-push/status` |
| `Connection refused: 8453`         | Push server chưa khởi động                 | Khởi động lại `grpc_push_client.py`               |
| Web Management không truy cập được | Gateway chưa expose cổng 9990              | Kiểm tra `docker-compose.yml` port mapping        |

### 10. Thời Gian

Khoảng **40 giây**.

---

## S8 — HTTP PULL TEST

### 1. Mục Đích

Kiểm tra cơ chế HTTP Pull — nơi Gateway gửi HTTP request đến một HTTP AS Server (cổng 8049) khi nhận MAP request `*519#`, và AS Server phản hồi lại qua HTTP response.

### 2. Phụ Thuộc

**S3** — Gateway phải đang chạy.

### 3. Lệnh Thủ Công

**Bước 1: Khởi động HTTP AS Server (cửa sổ riêng)**

```bash
cd /opt/ussdgw-prod-release
python3 http_as_server.py :8049
```

**Bước 2: Gửi MAP request từ Client**

```bash
cd /opt/ussdgw-prod-release
java -cp "lib/*:." Client 1 "*519#"
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S8"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ 1 (HTTP AS):** `http-as`

```bash
tmux new-window -t ussd-e2e-test -n http-as
python3 /opt/ussdgw-prod-release/http_as_server.py :8049
```

**Tên cửa sổ 2 (HTTP Pull Client):** `http-pull`

```bash
tmux new-window -t ussd-e2e-test -n http-pull
java -cp "/opt/ussdgw-prod-release/lib/*:/opt/ussdgw-prod-release/." Client 1 "*519#"
```

### 6. File Log

**HTTP AS Server:** `/tmp/ussd-logs/http-as.log`  
**HTTP Pull Client:** `/tmp/ussd-logs/http-pull.log`

```bash
python3 /opt/ussdgw-prod-release/http_as_server.py :8049 > /tmp/ussd-logs/http-as.log 2>&1 &
java -cp "/opt/ussdgw-prod-release/lib/*:/opt/ussdgw-prod-release/." Client 1 "*519#" > /tmp/ussd-logs/http-pull.log 2>&1
```

### 7. Kết Quả Mong Đợi

**`http-as.log`:**
```
HTTP AS Server listening on :8049
[REQUEST] POST /ussd - session=xyz789, msisdn=2519..., ussd_string=*519#
[RESPONSE] Sending 200 OK with menu content
```

**`http-pull.log`:**
```
Sending MAP_UNSTRUCTURED_SS_REQUEST with *519#
Received response: dialog completed
HTTP Pull test PASSED
```

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra HTTP AS Server nhận request
grep -q "POST /ussd" /tmp/ussd-logs/http-as.log && echo "[PASS] HTTP AS received request" || echo "[FAIL] No request"

# Kiểm tra dialog hoàn thành
grep -q "completed" /tmp/ussd-logs/http-pull.log && echo "[PASS] Pull dialog completed" || echo "[FAIL] Dialog not completed"
```

### 9. Xử Lý Sự Cố

| Lỗi                                  | Nguyên Nhân                           | Cách Khắc Phục                                  |
|--------------------------------------|---------------------------------------|-------------------------------------------------|
| `Address already in use: 8049`       | HTTP AS Server đã chạy                | Kill tiến trình cũ: `pkill -f http_as_server`   |
| Gateway không gọi HTTP AS            | Cấu hình HTTP Pull chưa đúng          | Kiểm tra cấu hình Gateway cho route `*519#`    |
| Timeout                               | HTTP AS phản hồi quá chậm             | Kiểm tra logic xử lý trong `http_as_server.py` |

### 10. Thời Gian

Khoảng **1 – 2 phút**.

---

## S9 — HTTP PUSH TEST

### 1. Mục Đích

Kiểm tra cơ chế HTTP Push — nơi Gateway chủ động gửi HTTP POST request đến endpoint `/restcomm` trên cổng 8080 khi có sự kiện USSD notification.

### 2. Phụ Thuộc

**S3** — Gateway phải đang chạy.

### 3. Lệnh Thủ Công

```bash
cd /opt/ussdgw-prod-release
python3 http_push_loadtest.py --target :8080/restcomm
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S9"]}}'
```

### 5. Cửa Sổ Tmux

**Tên cửa sổ:** `http-push`

```bash
tmux new-window -t ussd-e2e-test -n http-push
python3 /opt/ussdgw-prod-release/http_push_loadtest.py --target :8080/restcomm
```

### 6. File Log

**Đường dẫn:** `/tmp/ussd-logs/http-push.log`

```bash
python3 /opt/ussdgw-prod-release/http_push_loadtest.py --target :8080/restcomm > /tmp/ussd-logs/http-push.log 2>&1
```

### 7. Kết Quả Mong Đợi

```
HTTP Push Load Test
Target: :8080/restcomm
========================================
Starting HTTP Push load test...
[PROGRESS] Sent 100 push requests...
[PROGRESS] Sent 200 push requests...
...
========================================
Load test complete.
Total push requests: 500
Total errors: 0
Average latency: 12ms
Test PASSED
```

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra không có lỗi
grep -q "errors: 0" /tmp/ussd-logs/http-push.log && echo "[PASS] Zero HTTP push errors" || echo "[FAIL] HTTP push errors detected"

# Kiểm tra latency hợp lý
grep "Average latency" /tmp/ussd-logs/http-push.log
```

### 9. Xử Lý Sự Cố

| Lỗi                            | Nguyên Nhân                              | Cách Khắc Phục                               |
|--------------------------------|------------------------------------------|----------------------------------------------|
| `Connection refused: 8080`     | Gateway HTTP endpoint chưa sẵn sàng      | Kiểm tra Gateway đã expose cổng 8080         |
| `HTTP 404` trên `/restcomm`    | Endpoint không tồn tại                   | Kiểm tra cấu hình HTTP Push trên Gateway     |
| Latency cao (>100ms)           | Gateway quá tải hoặc tài nguyên hạn chế  | Giảm số lượng request, kiểm tra CPU Gateway  |

### 10. Thời Gian

Khoảng **40 giây**.

---

## S10 — DỪNG TẤT CẢ

### 1. Mục Đích

Dừng tất cả các tiến trình, Docker container, và dọn dẹp tài nguyên hệ thống sau khi hoàn thành test. Giữ lại tmux session để kiểm tra log nếu cần.

### 2. Phụ Thuộc

Không có — có thể chạy bất kỳ lúc nào để dừng toàn bộ hệ thống.

### 3. Lệnh Thủ Công

```bash
# Dừng tất cả tiến trình Python liên quan
pkill -f "ussd_as_server.py" 2>/dev/null
pkill -f "loadtest_client.py" 2>/dev/null
pkill -f "grpc_push_client.py" 2>/dev/null
pkill -f "http_as_server.py" 2>/dev/null
pkill -f "http_push_loadtest.py" 2>/dev/null
pkill -f "Client" 2>/dev/null
echo "Tất cả tiến trình Python/Java đã được dừng."

# Dừng Docker container
cd /opt/ussdgw-prod-release/gateway
docker compose down
echo "Docker container đã được dừng."

# Tmux session vẫn được giữ lại để kiểm tra log
echo "Tmux session 'ussd-e2e-test' được giữ lại."
echo "Dùng: tmux attach -t ussd-e2e-test  để xem log."
```

### 4. Lệnh Mastra

```bash
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S10"]}}'
```

### 5. Cửa Sổ Tmux

Không áp dụng — chạy đồng bộ, nhưng **giữ lại tmux session** `ussd-e2e-test` để kiểm tra.

### 6. File Log

Không tạo file log mới.

### 7. Kết Quả Mong Đợi

```
Tất cả tiến trình Python/Java đã được dừng.
Docker container đã được dừng.
Tmux session 'ussd-e2e-test' được giữ lại.
```

Xác nhận:

```bash
# Không còn tiến trình liên quan
pgrep -af "ussd_as_server\|loadtest_client\|grpc_push\|http_as_server\|http_push_loadtest" || echo "Không còn tiến trình nào — OK"

# Docker container đã dừng
docker ps --format "{{.Names}}" | grep -q "ussdgw" && echo "CẢNH BÁO: Container vẫn đang chạy!" || echo "Container đã dừng — OK"
```

### 8. Kiểm Tra Sức Khỏe

```bash
# Kiểm tra tổng thể
! pgrep -f "ussd_as_server.py" && ! pgrep -f "loadtest_client" && ! docker ps | grep -q "ussdgw" && echo "[PASS] All clean" || echo "[WARN] Some processes remain"
```

### 9. Xử Lý Sự Cố

| Lỗi                                      | Nguyên Nhân                          | Cách Khắc Phục                                    |
|------------------------------------------|--------------------------------------|---------------------------------------------------|
| Tiến trình không dừng được với `pkill`   | Tiến trình treo hoặc zombie          | `kill -9 $(pgrep -f "tên_tiến_trình")`           |
| `docker compose down` báo lỗi            | File `docker-compose.yml` không tìm thấy | Đảm bảo đang ở đúng thư mục `gateway/`         |
| Container vẫn chạy sau khi down          | Container được khởi động ngoài compose | `docker stop $(docker ps -q --filter "name=ussdgw")` |

### 10. Thời Gian

Khoảng **10 giây**.

---

## 🚀 CÁCH CHẠY TẤT CẢ SCENARIO

### Phương Pháp 1: Qua Mastra Workflow (Khuyến Nghị)

```bash
cd /opt/ussdgw-prod-release/ussd-qa-team/mastra

# Khởi động Mastra dev server
npx mastra dev

# Từ một terminal khác, chạy tất cả scenario tuần tự
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S0","S1","S2","S3","S4","S5","S6","S7","S8","S9"], "pcap": true}}'
```

> **Chú ý:** Khi `"pcap": true`, Mastra sẽ tự động bật `tcpdump` để bắt gói tin trong suốt quá trình test.

### Phương Pháp 2: Qua Script Riêng Lẻ (Thủ Công)

```bash
cd /opt/ussdgw-prod-release

# Khởi tạo thư mục log
mkdir -p /tmp/ussd-logs

# Tạo tmux session
tmux new-session -d -s ussd-e2e-test -n main

# S0: Kiểm tra môi trường
lsmod | grep sctp && java -version && python3 --version && docker info && test -d /opt/ussdgw-prod-release

# S1: Tải Docker image
bash scripts/01-load-docker-image.sh

# S2: Thiết lập máy chủ
sudo bash scripts/02-setup-host.sh

# S3: Khởi động Gateway (có monitor)
./scripts/03-start-gateway.sh --with-monitor

# S4: Khởi động gRPC AS
./scripts/05-start-grpc-as.sh

# S5: MAP Smoke test
./scripts/06-run-map-smoke.sh

# S6: gRPC Smoke test
./scripts/07-run-grpc-smoke.sh

# S7: gRPC Push test
./scripts/08-run-grpc-push.sh

# S8: HTTP Pull test
./scripts/09-run-http-pull.sh

# S9: HTTP Push test
./scripts/10-run-http-push.sh

# S10: Dừng tất cả
./scripts/stop-all.sh
```

### Phương Pháp 3: Chạy Từng Phần (Nhóm Scenario)

```bash
# Chỉ kiểm tra môi trường + khởi động
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S0","S1","S2","S3","S4"]}}'

# Chỉ chạy smoke test
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S5","S6"]}}'

# Chỉ chạy push/pull test
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S7","S8","S9"]}}'
```

---

## 📺 XEM LOG TRỰC TIẾP

### Tmux Session

Tmux session chính tên là `ussd-e2e-test` chứa tất cả các cửa sổ scenario:

```bash
# Gắn vào tmux session
tmux attach -t ussd-e2e-test

# Các phím tắt trong tmux:
# Ctrl-b 0..9  → Chuyển đến cửa sổ 0..9 tương ứng
# Ctrl-b n     → Cửa sổ kế tiếp
# Ctrl-b p     → Cửa sổ trước đó
# Ctrl-b d     → Thoát (detach) khỏi tmux
# Ctrl-b [     → Chế độ scroll (dùng phím mũi tên/PgUp/PgDn)
```

### Bảng Ánh Xạ Cửa Sổ Tmux

| Phím Tắt   | Cửa Sổ        | Nội Dung                          |
|------------|---------------|-----------------------------------|
| `Ctrl-b 0` | main          | Terminal chính                    |
| `Ctrl-b 1` | docker-gw     | Log Docker Gateway                |
| `Ctrl-b 2` | grpc-as       | Log gRPC Application Server       |
| `Ctrl-b 3` | map-smoke     | Log MAP Smoke Test                |
| `Ctrl-b 4` | grpc-smoke    | Log gRPC Smoke Test               |
| `Ctrl-b 5` | grpc-push     | Log gRPC Push Test                |
| `Ctrl-b 6` | http-as       | Log HTTP AS Server                |
| `Ctrl-b 7` | http-pull     | Log HTTP Pull Test                |
| `Ctrl-b 8` | http-push     | Log HTTP Push Test                |

### Tail File Log Trực Tiếp

```bash
# Xem log Docker Gateway
tail -f /tmp/ussd-logs/docker-gw.log

# Xem log gRPC AS
tail -f /tmp/ussd-logs/grpc-as.log

# Xem tất cả log cùng lúc
tail -f /tmp/ussd-logs/*.log

# Xem log với màu sắc (nếu có cài đặt)
tail -f /tmp/ussd-logs/docker-gw.log | grep --color -E "ERROR|WARN|INFO|FAIL|PASS|$"
```

### Kiểm Tra Trạng Thái Gateway

```bash
# Trạng thái container
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "ussdgw|NAMES"

# Resource usage
docker stats --no-stream $(docker ps -q --filter "name=ussdgw")

# Health check endpoint
curl -s http://localhost:8080/jolokia/version | python3 -m json.tool 2>/dev/null || echo "Gateway chưa sẵn sàng"
```

---

## 🔍 BẮT GÓI TIN (PCAP)

### Bắt Gói Tin Thủ Công

```bash
# Bắt tất cả gói tin SCTP (protocol 132) trên mọi interface
sudo tcpdump -i any -s 0 -w /tmp/ussd-e2e.pcap proto 132 &

# PID của tcpdump sẽ được in ra. Lưu lại để dừng sau.
TCPDUMP_PID=$!

# ... chạy các scenario test ...

# Dừng bắt gói tin
sudo kill $TCPDUMP_PID 2>/dev/null
```

### Bắt Gói Tin Với Bộ Lọc Chi Tiết

```bash
# Chỉ bắt SCTP giữa các cổng cụ thể
sudo tcpdump -i lo -s 0 -w /tmp/ussd-sctp.pcap 'proto 132 and port 8011 or port 8012' &

# Bắt cả HTTP + gRPC
sudo tcpdump -i any -s 0 -w /tmp/ussd-full.pcap 'proto 132 or port 8080 or port 8443 or port 8049' &
```

### Kiểm Tra File PCAP

```bash
# Thông tin tổng quan về file capture
capinfos /tmp/ussd-e2e.pcap

# Số lượng gói tin
tcpdump -r /tmp/ussd-e2e.pcap -nn | wc -l

# Xem nhanh nội dung
tcpdump -r /tmp/ussd-e2e.pcap -nn -A | head -100

# Phân tích bằng tshark (nếu có)
tshark -r /tmp/ussd-e2e.pcap -Y "sctp" -T fields -e frame.time -e sctp.srcport -e sctp.dstport 2>/dev/null
```

### Chạy Mastra Với PCAP Tự Động

```bash
# Mastra tự động bắt đầu/dừng tcpdump
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S5","S6"], "pcap": true, "pcapFile": "/tmp/ussd-e2e.pcap"}}'
```

---

## 📁 PHỤ LỤC: CẤU TRÚC THƯ MỤC

```
/opt/ussdgw-prod-release/
├── gateway/
│   ├── docker-compose.yml         # Docker Compose cho Gateway
│   └── Dockerfile                 # Dockerfile (nếu build từ source)
├── config/
│   ├── ussd-gateway-config.xml    # Cấu hình chính Gateway
│   └── slee-config.xml            # Cấu hình SLEE container
├── scripts/
│   ├── 01-load-docker-image.sh    # S1: Tải Docker image
│   ├── 02-setup-host.sh           # S2: Thiết lập máy chủ
│   ├── 03-start-gateway.sh        # S3: Khởi động Gateway
│   ├── 05-start-grpc-as.sh        # S4: Khởi động gRPC AS
│   ├── 06-run-map-smoke.sh        # S5: MAP Smoke Test
│   ├── 07-run-grpc-smoke.sh       # S6: gRPC Smoke Test
│   ├── 08-run-grpc-push.sh        # S7: gRPC Push Test
│   ├── 09-run-http-pull.sh        # S8: HTTP Pull Test
│   ├── 10-run-http-push.sh        # S9: HTTP Push Test
│   └── stop-all.sh                # S10: Dừng tất cả
├── lib/                           # Java JAR libraries
├── ussd_as_server.py              # S4: gRPC AS Server
├── loadtest_client.py             # S6: gRPC Load Test Client
├── grpc_push_client.py            # S7: gRPC Push Client
├── http_as_server.py              # S8: HTTP AS Server
├── http_push_loadtest.py          # S9: HTTP Push Load Test
├── Client.class / Client.java     # MAP Client
├── ussd-qa-team/
│   └── mastra/
│       ├── SCENARIO-GUIDE.vi.md   # ← File hướng dẫn này
│       ├── HOW-TO-RUN.md          # Hướng dẫn chạy nhanh
│       ├── src/                   # Mastra workflow source
│       ├── .mastra/               # Mastra config & state
│       └── package.json           # Node.js dependencies
└── docker/
    └── restcomm-ussd-*.tar.gz     # Docker image archive
```

### File Log Tập Trung

```
/tmp/ussd-logs/
├── docker-gw.log                  # S3: Gateway log
├── grpc-as.log                    # S4: gRPC AS log
├── map-smoke.log                  # S5: MAP smoke test log
├── grpc-smoke.log                 # S6: gRPC smoke test log
├── grpc-push.log                  # S7: gRPC push test log
├── http-as.log                    # S8: HTTP AS server log
├── http-pull.log                  # S8: HTTP pull client log
└── http-push.log                  # S9: HTTP push test log
```

---

## 🏁 QUY TRÌNH E2E HOÀN CHỈNH

```
S0 ──► S1 ──► S2 ──► S3 ──► S4 ──► S5 ──► S6
                        │         │
                        │         └──► S7 (gRPC Push)
                        │
                        ├──► S8 (HTTP Pull)
                        │
                        └──► S9 (HTTP Push)
                                  │
                                  ▼
                                 S10 (Dừng)
```

**Thời gian tổng cộng ước tính:** 8 – 15 phút (tùy hiệu năng máy chủ và tốc độ mạng).

---

## 📋 DANH SÁCH KIỂM TRA NHANH (QUICK CHECKLIST)

Trước khi chạy E2E test, hãy xác nhận từng mục sau:

- [ ] **S0:** `lsmod | grep sctp` — module SCTP đã nạp
- [ ] **S0:** `docker info` — Docker daemon đang chạy
- [ ] **S1:** `docker images restcomm-ussd` — Image đã được nạp
- [ ] **S2:** `ls /opt/ussdgw/data/*.xml` — File cấu hình tồn tại
- [ ] **S3:** `curl -s http://localhost:8080/jolokia/version` → HTTP 200
- [ ] **S4:** `ss -tlnp | grep 8443` — gRPC AS đang lắng nghe
- [ ] **S5:** `grep "Total completed dialogs = 10" /tmp/ussd-logs/map-smoke.log`
- [ ] **S6:** `grep "errors: 0" /tmp/ussd-logs/grpc-smoke.log`
- [ ] **S7:** `grep "Received USSD notification" /tmp/ussd-logs/grpc-push.log`
- [ ] **S8:** `grep "completed" /tmp/ussd-logs/http-pull.log`
- [ ] **S9:** `grep "errors: 0" /tmp/ussd-logs/http-push.log`
- [ ] **S10:** `! docker ps | grep -q ussdgw` — Không còn container chạy

---

> 💡 **Mẹo:** Luôn chạy S0 trước để đảm bảo môi trường sạch. Nếu một scenario thất bại, kiểm tra file log tương ứng trong `/tmp/ussd-logs/` trước khi chạy lại. Sử dụng `tmux attach -t ussd-e2e-test` để xem toàn bộ log theo thời gian thực trong khi test đang chạy.

> ⚠️ **Cảnh báo:** Không chạy S10 trước khi hoàn tất kiểm tra log. Sau S10, Docker container đã dừng và không thể xem lại log container trừ khi đã lưu vào file log trong `/tmp/ussd-logs/`.
