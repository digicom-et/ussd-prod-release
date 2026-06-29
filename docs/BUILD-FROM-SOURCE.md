# 🏗️ Build USSD Gateway from Source — Hướng dẫn đầy đủ

> **Mục đích:** Build Docker image từ source code (ussdgateway + jain-slee-http-okhttp + jain-slee)
> **Áp dụng cho:** Developer muốn build phiên bản tự chỉnh sửa

---

## 1. Yêu cầu hệ thống

| Thành phần | Yêu cầu |
|-----------|---------|
| OS | Linux (Ubuntu 20.04+, CentOS 7+) |
| RAM | ≥ 8 GB (khuyến nghị 16 GB cho full build) |
| Disk | ≥ 20 GB free |
| Java | JDK 8 (Eclipse Temurin 8 khuyến nghị) |
| Maven | 3.6+ |
| Docker | 24+ với BuildKit |
| Python | 3.8+ (cho scripts) |

```bash
# Kiểm tra
java -version          # must be 1.8
mvn --version          # must be 3.6+
docker --version       # must be 24+
```

---

## 2. Cấu trúc repositories

```
ethiopia-working-dir/
├── ussdgateway/              # ★ Main USSD Gateway project
│   ├── core/                 # Core modules (xml, domain, slee, cluster...)
│   ├── management/           # Web UI
│   ├── tools/                # Test tools (gRPC tester, HTTP simulator)
│   ├── test/                 # Load tests
│   └── release-wildfly/      # ★ Build scripts + Docker (quan trọng)
│
├── jain-slee-http-okhttp/   # HTTP Client RA (OkHttp) + HTTP Servlet RA
│   └── resources/
│       ├── http-client/      # OkHttp client RA (sync)
│       ├── http-client-nio/  # Apache HttpAsyncClient RA (NIO, MỚI)
│       └── http-servlet/     # HttpServlet RA (sync)
│
├── jain-slee/               # JAIN SLEE container (SLEE 1.1, AS7 modules)
│   └── jain-slee/container/build/as7/  # ★ SLEE AS7 modules
│
├── jain-slee.ss7/           # SS7 Resource Adaptors (MAP, SCCP, TCAP, M3UA...)
│   └── resources/map/        # ★ MAP RA
│
└── jSS7/                    # Restcomm jSS7 stack
```

---

## 3. Build quy trình (Step-by-Step)

### 3.1. Pre-build: Cài đặt Restcomm parent POM

```bash
cd ethiopia-working-dir/ussdgateway

# Restcomm parent POM (bắt buộc cho dependency management)
# Nếu chưa có sẵn trong local Maven repo (~/.m2/repository/org/mobicents/restcomm-parent/):
mvn install -N -f pom.xml  # install parent POM
```

### 3.2. Bước 1: Build JAIN SLEE AS7 modules

```bash
cd ethiopia-working-dir/jain-slee/jain-slee/container/build/as7
mvn clean package -Dmaven.test.skip=true
```

SLEE AS7 modules bao gồm:
- `slee-container-module` — JAIN SLEE container
- `slee-ra-type-module` — Resource Adaptor types
- `slee-facilities-module` — Timer, Alert, Trace
- `slee-wildfly-subsystem` — WildFly subsystem integration

### 3.3. Bước 2: Build HTTP Servlet RA

```bash
cd ethiopia-working-dir/jain-slee-http-okhttp/resources/http-servlet
mvn clean install -Dmaven.test.skip=true
```

HttpServlet RA là module bắt buộc cho USSD Gateway HTTP entry point.

### 3.4. Bước 3: Build MAP RA

```bash
cd ethiopia-working-dir/jain-slee.ss7/resources/map
mvn clean install -Dmaven.test.skip=true
```

MAP RA là module bắt buộc cho MAP protocol handling.

### 3.5. Bước 4: Build USSD Gateway (Maven full)

```bash
cd ethiopia-working-dir/ussdgateway

# Build toàn bộ project (bao gồm test)
mvn clean install -DskipTests=false  # hoặc -DskipTests để bỏ qua test

# Nếu chỉ muốn compile + test (không deploy)
mvn clean verify
```

Các module được build:
- `core/xml` — Jackson XML serialization
- `core/domain` — Config, routing rules
- `core/slee/sbbs` — SBB implementations
- `core/slee/resources/grpc-as` — gRPC AS RA (MỚI)
- `core/slee/resources/cdr-local` — CDR local RA
- `core/cluster` — Infinispan clustering
- `management/ussd-management` — Web UI
- `tools/grpc-as-tester` — gRPC test tools

### 3.6. Bước 5: Build Linux release package

```bash
cd ethiopia-working-dir/ussdgateway/release-wildfly

# Ant build: tạo linux distro (wildfly + SLEE modules + config)
ant -f build-linux.xml clean release
```

Output: `release-wildfly/target/wildfly-10.0.0.Final/`

### 3.7. Bước 6: Build Docker image

```bash
cd ethiopia-working-dir/ussdgateway/release-wildfly

# Cách 1: Script tự động (gộp B1-B4 + B6)
./build-docker.sh

# Cách 2: Thủ công (nếu đã chạy ant release)
docker build \
  --build-arg "USSD_VERSION=7.3.1" \
  -t "restcomm-ussd:7.3.1" \
  -t "restcomm-ussd:latest" \
  .

# Kiểm tra
docker images | grep restcomm-ussd
```

> **Lưu ý:** `build-docker.sh` tự động chạy Maven rebuild cho SLEE + HTTP + MAP trước.
> Nếu bạn đã build thủ công ở B1-B3, có thể comment bỏ các bước đó trong script.

---

## 4. Các tùy chọn build

### 4.1. Build nhanh (skip tests)

```bash
# Toàn bộ project
mvn clean install -DskipTests -T 4   # -T 4: 4 threads

# Chỉ một module
mvn clean install -pl core/xml -am -DskipTests
```

### 4.2. Release package với version tùy chỉnh

```bash
export USSD_VERSION=7.3.0-RC1
./build-docker.sh
```

### 4.3. Chỉ build Linux package (không Docker)

```bash
cd release-wildfly
ant -f build-linux.xml clean release
# Output: target/wildfly-10.0.0.Final/
```

### 4.4. Export Docker image để deploy server khác

```bash
# Save image thành tar
docker save restcomm-ussd:7.3.1 -o restcomm-ussd-7.3.1.tar

# Copy lên server
tar czfh - restcomm-ussd-7.3.0-SNAPSHOT.tar | ssh user@server "tar xzf - -C /opt/ussdgw/docker/"
```

---

## 5. Deploy với ussdgw-prod-release

### 5.1. Build package test

```bash
# Sau khi có Docker image:
cd ethiopia-working-dir/ussdgw-prod-release

# Build package (copy tools, scripts, gateway config)
./scripts/build-package.sh

# Đóng gói
tar czf ussdgw-prod-release-7.3.1.tar.gz -C .. ussdgw-prod-release
```

### 5.2. Deploy lên server test

```bash
# Copy lên server
scp ussdgw-prod-release-7.3.0-SNAPSHOT.tar.gz user@test-server:/opt/

# Trên test server
cd /opt
tar xzf ussdgw-prod-release-7.3.0-SNAPSHOT.tar.gz
cd ussdgw-prod-release

# Pre-flight check
./scripts/00-preflight.sh

# Load Docker image
./scripts/01-load-docker-image.sh

# Start gateway
cd gateway
docker compose up -d

# Kiểm tra health
curl -fs http://localhost:8080/jolokia/version && echo " OK"
```

### 5.3. Smoke test

```bash
cd /opt/ussdgw-prod-release

# HTTP Pull test
./scripts/12-run-http-pull-smoke.sh

# HTTP Push test
./scripts/13-run-http-push-smoke.sh

# gRPC Push test
./scripts/14-run-grpc-push-smoke.sh
```

---

## 6. Troubleshooting

### Build fails: Unresolved compilation

```
[ERROR] Failed to execute goal org.apache.maven.plugins:maven-compiler-plugin ...
  Unresolved compilation problems:
```

**Fix:**
1. Kiểm tra `JAVA_HOME` trỏ đúng JDK 8
2. `mvn clean` trước khi build lại
3. Kiểm tra dependency có trong `~/.m2/repository` không

### Build fails: Cannot find restcomm-parent

```
[ERROR] Non-resolvable parent POM for org.mobicents.ussd:parent:7.3.0-SNAPSHOT
```

**Fix:** Cài restcomm-parent từ local:
```bash
# Tìm restcomm-parent trong thư mục dự án
find /home/meodien/Desktop/ethiopia-working-dir -name "restcomm-parent" -type d

# Hoặc cài parent POM trực tiếp
cd ethiopia-working-dir/ussdgateway
mvn install -N
```

### Ant build fails: xmltask.jar not found

```
BUILD FAILED: .../release-wildfly/build-linux.xml:... xmltask.jar
```

**Fix:** `xmltask.jar` đã có sẵn trong `release-wildfly/`. Nếu thiếu:
```bash
# Download xmltask
wget https://github.com/ladykoishi/xmltask/releases/download/1.16/xmltask.jar
```

### Docker build: exec format error (architecture mismatch)

**Fix:** Build trên cùng kiến trúc với server target (amd64 vs arm64):
```bash
# Force build cho linux/amd64
docker build --platform linux/amd64 \
  --build-arg "USSD_VERSION=7.3.0-SNAPSHOT" \
  -t "restcomm-ussd:7.3.0-SNAPSHOT" .
```

### wildfly-10.0.0.Final-cleaned.zip không tìm thấy

**Fix:** File zip này đã có trong `release-wildfly/`. Nếu thiếu:
```bash
# Download WildFly 10.0.0.Final
wget https://download.jboss.org/wildfly/10.0.0.Final/wildfly-10.0.0.Final.zip
# Clean các module không cần thiết (SLEE, SIP, SS7 conflicts)
# Xem extract-wildfly.py để biết chi tiết
```

---

## 7. Kiến trúc build (cho maintainer)

```
                              ┌─────────────────────────┐
                              │   build-docker.sh       │
                              │   (Step 0-2 tự động)    │
                              └──────┬──────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
     ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
     │ jain-slee/as7   │   │ jain-slee-http- │   │ jain-slee.ss7   │
     │ (SLEE module)   │   │ okhttp/http-srv │   │ /resources/map  │
     │ mvn package     │   │ mvn install     │   │ mvn install     │
     └────────┬────────┘   └────────┬────────┘   └────────┬────────┘
              └──────────────────────┼──────────────────────┘
                                     ▼
                          ┌─────────────────────┐
                          │ build-linux.xml     │
                          │ (Ant: verify +      │
                          │  create distro)     │
                          └──────────┬──────────┘
                                     ▼
                          ┌─────────────────────┐
                          │ Docker build        │
                          │ (Dockerfile +       │
                          │  docker-entrypoint) │
                          └──────────┬──────────┘
                                     ▼
                          ┌─────────────────────┐
                          │ restcomm-ussd:VERSION│
                          │ (Docker image)      │
                          └─────────────────────┘
```

---

## 8. Các file build quan trọng

| File | Vai trò |
|------|---------|
| `ussdgateway/pom.xml` | Maven parent POM, dependency management |
| `ussdgateway/release-wildfly/build.xml` | Ant build cho Windows/Unix distro |
| `ussdgateway/release-wildfly/build-linux.xml` | Ant build cho Linux distro |
| `ussdgateway/release-wildfly/build-docker.sh` | Script build toàn bộ (Maven + Ant + Docker) |
| `ussdgateway/release-wildfly/Dockerfile` | Docker image definition |
| `ussdgateway/release-wildfly/extensions-build.xml` | Build SLEE + SS7 extensions modules |
| `ussdgateway/release-wildfly/standalone-patched.xml` | WildFly config với SLEE subsystem |
| `ussdgateway/release-wildfly/extract-wildfly.py` | Extract + clean WildFly base |
| `ussdgw-prod-release/scripts/build-package.sh` | Build test package từ Docker image |

---

*Hết — 2026-06-28*
