# MAP USSD Load Test — Multi-Menu + Adaptive Timeout

Aligns jSS7 `map/load` with `ussdgateway` demo config and the gRPC Python tester menu tree.

## Demo alignment (must match ussdgw)

| Parameter | Value |
|-----------|-------|
| SCTP | client `127.0.0.1:8011` → GW `127.0.0.1:8012` |
| M3UA RC / NA | 101 / 102 |
| OPC / DPC | 1 / 2 |
| USSD SSN | **8** (not 147) |
| MSC / HLR SSN | 8 / 6 |
| Default short code | `*100#` (gRPC) or `*519#` (HTTP demo) |
| Menu tree | `src/main/resources/menu_config.json` (same as `ussdgateway/tools/grpc-as-tester/menu_config.json`) |

## Build

**From jSS7 source (dev machine):**

```bash
cd jSS7/map/load
ant -f ussd_build.xml clean assemble
# or
cd jSS7/map && mvn install -N -DskipTests && cd load && mvn clean package -Passemble -DskipTests
```

Output: `jSS7/map/load/target/load/map-load.jar` + dependencies.

**From ussdgw-prod-release package** (pre-built by `ussdgw-prod-release/scripts/build-package.sh`):

```bash
cd ussdgw-prod-release/tools/jss7-map-load
ls lib/map-load.jar lib/*.jar   # map-load.jar + all runtime deps
```

## Run against USSD Gateway

1. Start ussdgw (Docker or WildFly) with SCTP 8012.
2. Add scrule for gRPC: `*100#` → `127.0.0.1:8443`.
3. Start gRPC AS: `python3 ussd_as_server.py --port 8443 --menu-config menu_config.json`
4. Enable bridge (optional): `sessionbridgeenabled=true`, `asyncgatetimeoutms=7000`.
5. Run MAP load client:

**ussdgw-prod-release package** (use `lib/*`, not `target/load/*`):

```bash
cd ussdgw-prod-release/tools/jss7-map-load
java -cp "lib/*" org.restcomm.protocols.ss7.map.load.ussd.Client \
  1000 50 sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP 101 102 1 2 3 2 8 6 8 \
  1111112 9960639999 1 16 -100 0 "*100#" RANDOM 50 200
```

**From jSS7 source:**

```bash
cd jSS7/map/load
ant -f ussd_build.xml client
# or direct java with profile + think delay:
java -cp "target/load/*" org.restcomm.protocols.ss7.map.load.ussd.Client \
  1000 50 sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP 101 102 1 2 3 2 8 6 8 \
  1111112 9960639999 1 16 -100 0 "*100#" RANDOM 50 200
```

### CLI args (extended)

| Pos | Name | Default |
|-----|------|---------|
| 24 | duration minutes | 0 (count mode) |
| 25 | USSD string | `*100#` |
| 26 | menu profile | `RANDOM` (`BALANCE`, `DATA`, `SUBSCRIBE`, `ADAPTIVE`) |
| 27 | think min ms | 0 |
| 28 | think max ms | 0 |

**Think delay** (args 27–28): random sleep before each user digit — exercises gateway EWMA/adaptive gate with multi-turn dialogs without overrunning TCAP timeout.

**ADAPTIVE profile**: same menu paths as RANDOM; pair with think delay 50–500 ms and gRPC AS `--min-delay 1 --max-delay 100`.

## TPS warmup (default ON)

All load generators ramp TPS over the first **60 seconds** before reaching the configured target. Steps: `1 → 100 → 500 → 1000 → 2000 → 3000 → 5000 → 7000 → 10000` (capped at `--tps` / `MAXCONCURRENTDIALOGS`). Avoids slamming full rate into USSD GW before JVM/SLEE/TCAP are ready.

| Tool | Disable warmup |
|------|----------------|
| gRPC `loadtest_client.py` | `--no-warmup` |
| HTTP `http_push_loadtest.py` | `--no-warmup` |
| MAP `Client.java` | `-Dwarmup=false` |

Example (gRPC, 5000 TPS target):

```
warmup 60s: 1 → 100 → 500 → 1000 → 2000 → 3000 → 5000 TPS
```

MAP client prints the same summary at startup via `WarmupRateHelper.summary(MAXCONCURRENTDIALOGS)`.

## jSS7 MAP Simulator

**ussdgw-prod-release package:**

```bash
cd ussdgw-prod-release/tools/jss7-simulator/bin
chmod +x run.sh
./run.sh gui --name=main
```

Config is pre-seeded at `ussdgw-prod-release/tools/jss7-simulator/data/main_simulator2.xml`.

**From jSS7 source:**

```bash
cd jSS7
mvn clean install -pl tools/simulator -am -Dmaven.test.skip=true
cd tools/simulator/bootstrap/target/simulator-ss7/bin
chmod +x run.sh
./run.sh gui --name=main
```

Load config from `ussdgateway/core/bootstrap/src/main/config/ss7-simulator/main_simulator2.xml` into `data/main_simulator2.xml`.

## gRPC Python multi-menu load

```bash
cd ussdgateway/tools/grpc-as-tester
python3 loadtest_client.py --target localhost:8443 --tps 500 --duration 30 --multi-menu --profile BALANCE
```
