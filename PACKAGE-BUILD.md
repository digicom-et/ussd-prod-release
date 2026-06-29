# Building `ussdgw-prod-release` package (maintainers)

Mỗi lần tạo package mới phải **đủ 4 phần**:

| Phần | Nguồn | Đích trong package |
|------|--------|-------------------|
| Docker image | `ussdgateway/release-wildfly` (`./build-docker.sh`) | `docker/restcomm-ussd-alpine-7.3.1.tar` |
| Gateway | `release-wildfly` compose + config-seed | `gateway/` |
| Scripts | `ussdgw-prod-release/scripts/` (giữ trong repo/package) | `scripts/` |
| **Test tools** | xem bảng dưới | `tools/` |

## Test tools (bắt buộc copy mỗi lần build)

| Tool | Nguồn dev | Đích package | Ghi chú |
|------|-----------|--------------|---------|
| MAP load client | `jSS7/map/load` | `tools/jss7-map-load/` | `mvn -Passemble` → `lib/*` + `USSD-LOADTEST.md` + `menu_config.json` |
| SS7 simulator | `jSS7/tools/simulator` | `tools/jss7-simulator/` | `mvn install -pl tools/simulator` → distro + `main_simulator2.xml` |
| gRPC tester | `ussdgateway/tools/grpc-as-tester` | `tools/grpc-as-tester/` | `*.py`, `requirements.txt`, `wheels/` offline |
| HTTP simulator | `ussdgateway/tools/http-simulator` | `tools/http-simulator/` | GUI distro + `loadtest/` pull/push auto XML |

## Lệnh build full (một lần)

```bash
# 1. Build gateway Docker image (nếu chưa có)
cd ussdgateway/release-wildfly
./build-docker.sh

# 2. Build toàn bộ package
cd ../../ussdgw-prod-release
./scripts/build-package.sh

# 3. Đóng gói zip/tar đem lên server
tar czf ussdgw-prod-release-7.3.1.tar.gz -C .. ussdgw-prod-release
```

Chỉ sync tools + gateway (không export docker lại):

```bash
SKIP_DOCKER=1 ./scripts/build-package.sh
```

## Kiểm tra sau build

```bash
./scripts/00-preflight.sh
```

Phải thấy: docker tar, MAP load JARs, gRPC scripts, simulator `run.jar`.
