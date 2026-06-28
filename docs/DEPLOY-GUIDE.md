# 🚀 USSD Gateway Docker Deploy Guide

## 1. Build Docker Image

```bash
cd ussdgateway/release-wildfly
./build-docker.sh
```

Script thực hiện:
1. `mvn clean package` — rebuild SLEE AS7 modules (`jain-slee/.../container/build/as7`)
2. `ant -f build-linux.xml clean release` — verify SLEE JARs (không chứa `Unresolved compilation`)
3. `docker build` — tag `restcomm-ussd:7.2.1-SNAPSHOT`

> **Không** dùng `docker build` trực tiếp nếu chưa chạy ant release — image có thể chứa SLEE extension JAR lỗi.

With `network_mode: host`, entrypoint tự thêm hostname (`ussd-prod`) vào `/etc/hosts` — tránh `UnknownHostException` khi WildFly boot.

> **Docker context:** Trên máy có nhiều context (ví dụ `desktop-linux` vs `default`), dùng **cùng một context** cho build và deploy:
> ```bash
> docker context use default   # hoặc context gắn với /opt/ussdgw trên host
> docker context show
> ```
> Build ở context A rồi `docker compose up` ở context B → container chạy image cũ hoặc thiếu volume mount.

## 2. Chạy USSD Gateway Container

### Option A: Docker Run (đơn giản)

```bash
# Tạo volume cho data/log
docker volume create ussdgw-data
docker volume create ussdgw-logs

# Chạy container với 5GB RAM limit
docker run -d \
  --name ussdgw-prod-release \
  --memory=5g \
  --cpus=2.0 \
  -p 8080:8080 \
  -p 9990:9990 \
  -p 2905:2905/sctp \
  -v ussdgw-data:/opt/ussdgw/data \
  -v ussdgw-logs:/opt/ussdgw/log \
  --restart=unless-stopped \
  restcomm-ussd:7.2.1-SNAPSHOT
```

### Option B: Docker Compose (khuyến nghị)

```bash
cd ussdgateway/release-wildfly
docker compose -f docker-compose.test.yml up -d
```

## 3. Kiểm tra trạng thái

```bash
# Xem logs
docker logs -f ussdgw-prod-release

# Health check
docker exec ussdgw-prod-release curl -fs http://localhost:9990/health

# Management console
curl http://localhost:9990
```

## 3b. USSD Management GUI

| Item | Value |
|------|--------|
| URL | http://localhost:8080/ussd-management/ |
| Default login | `admin` / `admin` |
| Role required | `JBossAdmin` (in `mgmt-groups.properties`) |

Credentials are **baked into the Docker image** and **persisted on the host**:

```
/opt/ussdgw/configuration/mgmt-users.properties   → admin=admin
/opt/ussdgw/configuration/mgmt-groups.properties  → admin=JBossAdmin
```

On container start, entrypoint overlays `configuration/` → `wildfly/standalone/configuration/`.
To change password: edit host files under `/opt/ussdgw/configuration/`, restart container.

Seed source (package): `gateway/config-seed/configuration/mgmt-*.properties`

## 4. Cấu hình SS7 Stack (sau khi container chạy)

Data configs được mount tại `/opt/ussdgw/data/`. Các file mẫu đã được copy từ image:

```
/opt/ussdgw/data/
├── Mtp3UserPart_m3ua1.xml
├── SccpStack_management2.xml
├── SccpStack_sccpresource2.xml
├── SccpStack_sccprouter2.xml
├── SCTPManagement_sctp.xml
├── TcapStack_management.xml
├── UssdManagement_scroutingrule.xml
└── UssdManagement_ussdproperties.xml
```

Chỉnh sửa config SS7 phù hợp với môi trường lab/production, sau đó restart container.

## 5. Chạy MAP Load Test

### 5.1 Loopback Test (không cần SS7 network)

```bash
cd ussdgateway/test/loadtest
mvn clean package -DskipTests

# Chạy server + client loopback
./run-test-lab.sh configuration.conf loopback
```

### 5.2 HTTP Load Test (yêu cầu USSD GW đang chạy)

```bash
cd ussdgateway/test/loadtest
./run-test-lab.sh configuration.conf http
```

### 5.3 Real SS7 Test (yêu cầu SS7 stack config đúng)

```bash
# 1. Start bootstrap stack trước
cd ussdgateway/test/bootstrap
mvn clean package -DskipTests
./run.sh

# 2. Chạy load generator
cd ussdgateway/test/loadtest
java -XX:+UseG1GC -Xms4g -Xmx4g \
  -cp "target/loadtest-7.2.1-SNAPSHOT.jar:target/dependency/*" \
  org.mobicents.ussd.loadtest.UssdLoadTestMain \
  --client --ssn 8 --tps 10000 --threads 20
```

## 6. JVM Options trong Container

| Option | Giá trị | Ý nghĩa |
|--------|---------|---------|
| `-Xms4g -Xmx4g` | 4GB heap | Memory cố định cho USSD GW |
| `-XX:+UseG1GC` | G1GC | Garbage collector cho large heap |
| `-XX:MaxGCPauseMillis=200` | 200ms | Target GC pause |
| `-XX:+UseContainerSupport` | Enabled | Auto-detect container limits |
| `-XX:MaxRAMPercentage=75.0` | 75% | Dùng 75% container memory |
| `-Djava.net.preferIPv4Stack=true` | IPv4 | Force IPv4 |

## 7. Troubleshooting

| Vấn đề | Fix |
|--------|-----|
| Container exit immediately | Kiểm tra `docker logs ussdgw-prod-release` |
| Health check fail | Đợi 2-3 phút để WildFly khởi động xong |
| SS7 không kết nối | Kiểm tra `SCTPManagement_sctp.xml`, `Mtp3UserPart_m3ua1.xml` |
| OutOfMemory | Tăng `--memory` hoặc giảm `-Xmx` |
| Permission denied | Kiểm tra volume mount permissions |

## 8. Production Notes

- Dùng `docker-compose.test.yml` với `restart: unless-stopped`
- Mount `standalone.conf` tùy chỉnh qua volume
- Backup `/opt/ussdgw/data` định kỳ
- Theo dõi logs qua `docker logs -f ussdgw-prod-release`
