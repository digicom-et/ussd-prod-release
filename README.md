# USSD Gateway — የፕሮዳክሽን ልቀት ጥቅል (Prod Release Package)

ይክፈቱ → ስክሪፕቱን ያስኪዱ → ያረጋግጡ። **መገንባት አያስፈልግም (build አያስፈልግም)።**

---

## ፈጣን አፈፃፀም (ደረጃ በደረጃ ይቅዱና ይለጥፉ)

### ደረጃ 1 — ይክፈቱና ወደ ማውጫው ይግቡ

```bash
cd /opt
tar xzf ussdgw-prod-release-7.3.1.tar.gz
cd ussdgw-prod-release
```

### ደረጃ 2 — SCTP + ማረጋገጫ

```bash
lsmod | grep sctp          # የsctp መስመር መታየት አለበት
# ባዶ ከሆነ:
sudo modprobe sctp

chmod +x scripts/*.sh
./scripts/00-preflight.sh
```


### ደረጃ 3 — የDocker ምስል ይጫኑ (በመጠባበቂያ አስተናጋጅ ላይ፣ GW ሳይቆም)

```bash
./scripts/01-load-docker-image.sh
```

→ `/opt/ussdgw`ን (ካለ) ወደ `backups/` ያስቀምጣል፣ tar ይጫናል፣ **ለመመለሻ (rollback) የቀድሞውን ምስል ያስቀምጣል**።

### ደረጃ 3b — መቀየር (ማሻሻል) ወይም አዲስ ጭነት ከሆነ መተው

```bash
./scripts/03-switch-gateway.sh
```

### ደረጃ 3c — መመለሻ (Rollback) — አዲሱ ስሪት ብልሽት ካለው

```bash
./scripts/03-switch-gateway.sh --rollback
sudo ./scripts/02-setup-host.sh --restore backups/ussdgw-<timestamp>/
```

### ደረጃ 4 — አስተናጋጅ ማዋቀር (Setup host)

```bash
sudo ./scripts/02-setup-host.sh
```


### ደረጃ 5 — USSD Gateway ያስነሱ (`docker compose up`) ⭐

```bash
./scripts/03-start-gateway.sh                # ጌትዌይ ብቻ
./scripts/03-start-gateway.sh --with-monitor # ጌትዌይ + BPF ሰብሳቢ (collector) headless
curl -fs http://localhost:8080/jolokia/version && echo " OK"
```

ወይም ዋናውን compose በቀጥታ ይጠቀሙ:

```bash
cd ussdgw-prod-release          # ከጥቅሉ ሥር ማውጫ (package root) ላይ ይቁሙ
docker compose -f docker-compose.yml up -d ussdgw
docker compose -f docker-compose.yml up -d collector   # አማራጭ — BPF TPS መቆጣጠሪያ
```

### ደረጃ 6–9

`docs/e2e-grpc-ussd-test.md` ይመልከቱ — ለእያንዳንዱ ደረጃ **ስክሪፕት** እና **「በእጅ መተካት」** (ለእያንዳንዱ መሣሪያ የተለየ ትዕዛዝ) አለው።

| ደረጃ | ፈጣን ስክሪፕት | በእጅ መሣሪያ |
|------|--------------|---------------|
| 6 gRPC AS | `05-start-grpc-as.sh` | `ussd_as_server.py :8443` |
| 7 MAP smoke | `06-run-map-smoke.sh` | `java ... Client ... "*100#" BALANCE` |
| 8 gRPC load | `07-run-grpc-smoke.sh` | `loadtest_client.py` |
| 8b gRPC Push | `14-run-grpc-push-smoke.sh` | `grpc_push_client.py :8453` |
| 9 ማቆም | `stop-all.sh` | `compose down` + kill AS PID |

አዲስ ጭነትን በአንድ ላይ: `sudo ./scripts/start-all.sh`

የተሟላ የትዕዛዝ ሰንጠረዥ: [አባሪ A](docs/e2e-grpc-ussd-test.md#phụ-lục-a--chạy-thủ-công-từng-công-cụ-thay-thế-script)።


---

## መጠባበቂያ እና መመለሻ (Backup & Rollback)

| አካል | ትዕዛዝ |
|------------|------|
| የአስተናጋጅ መጠባበቂያ `/opt/ussdgw` | በ`01-load`፣ `03-switch`፣ `02-setup` ውስጥ በራስ-ሰር ይከናወናል |
| መጠባበቂያዎችን ይዘርዝሩ | `./scripts/02-setup-host.sh --list-backups` |
| አስተናጋጅ መልሶ ማቋቋም | `sudo ./scripts/02-setup-host.sh --restore backups/ussdgw-*/` |
| በዲስክ ላይ ያለ የቀድሞ ምስል | `docker images restcomm-ussd` |
| ምስል መመለሻ | `./scripts/03-switch-gateway.sh --rollback` |
| የተወሰነ ምስል ምረጡ | `./scripts/03-switch-gateway.sh --to <tag>` |

---

## ዝርዝር መመሪያዎች

| ፋይል | ይዘት |
|------|----------|
| `docs/e2e-grpc-ussd-test.md` | የE2E መመሪያ (በቬትናምኛ - VI) |
| `docs/e2e-grpc-ussd-test_en.md` | የE2E መመሪያ (በእንግሊዝኛ - EN) |
| `docs/DEPLOY-GUIDE.md` | የDocker ምስል ማሰማራት (ለዋና ተጠቃሚ) |
| `docs/BUILD-FROM-SOURCE.md` | **የDocker ምስል ከምንጭ ኮድ መገንባት (ለገንቢ - developer)** |
| `tools/jss7-map-load/USSD-LOADTEST.md` | MAP load CLI — `lib/*`ን የሚጠቀም ጥቅል |

ከሙከራ በፊት `./scripts/00-preflight.sh` ያስኪዱ — `map-load.jar`፣ Woodstox፣ docker tar ያረጋግጣል።


---

## የጥቅሉ መዋቅር (Package Structure)

```
ussdgw-prod-release/
├── backups/              # ussdgw-host.tgz (01/02/03 ሲሰራ ይፈጠራል)
├── docker/               # የምስል tar + package.manifest
├── gateway/              # compose + .env + config-seed + configuration/
├── tools/
├── docs/
└── scripts/
```

የአስተናጋጅ ቀጣይነት (compose volumes):

| የአስተናጋጅ ዱካ (Host path) | ኮንቴይነር | ዓላማ |
|-----------|-----------|---------|
| `/opt/ussdgw/data` | SS7/USSD XML | የስታክ + ራውቲንግ ውቅር |
| `/opt/ussdgw/log` | WildFly logs | server.log |
| `/opt/ussdgw/configuration` | `standalone/configuration` | GUI ማረጋገጫ (`mgmt-users.properties`) |

አዲስ ጥቅል መፍጠር (በግንባታ ማሽን ላይ):

```bash
cd ussdgateway/release-wildfly && ./build-docker.sh
docker context use default   # ሲጭኑ/ሲያሰማሩ ተመሳሳይ context ይጠቀሙ
cd ../../ussdgw-prod-release && ./scripts/build-package.sh
tar czf ussdgw-prod-release-7.3.1.tar.gz -C .. ussdgw-prod-release
```

ከ`build-package.sh` በኋላ `docker/package.manifest` (BUILD_ID) እና `./scripts/00-preflight.sh` ያረጋግጡ።

## ወደቦች (Ports)

| ወደብ | አገልግሎት |
|------|---------|
| 8012 | SCTP Gateway |
| 8011 | MAP client |
| 8443 | gRPC AS |
| 8453 | gRPC Push (NI) |
| 8049 | HTTP Pull AS |
| 8080 | HTTP + Jolokia health (`/jolokia/version`) |
| 9090 | **BPF ሰብሳቢ መለኪያዎች (collector metrics)** (`/metrics`, `/healthz`) |
| 9990 | WildFly አስተዳደር API |

---

## 📊 BPF/M3UA TPS መቆጣጠሪያ + Live TUI ዳሽቦርድ (አዲስ)

ሙሉው ቁልል (stack) የሚሰራው በአንድ **ነጠላ `docker-compose.yml`** ሲሆን ከጥቅሉ ሥር ማውጫ (package root) ላይ ነው
(`docker-compose.yml`) 4 አገልግሎቶችን ያካትታል: `init`፣ `ussdgw`፣ `collector`፣ `tui`።

```
┌─────────────────────────────────────────────────────────────────────┐
│ ዋና compose (docker-compose.yml)                                    │
│                                                                     │
│  init (alpine, one-shot) → /opt/ussdgw ዘርቶ ያስቀምጣል               │
│           ↓                                                         │
│  ussdgw (network_mode: host, Zulu 8 JDK, Wildfly 10)          │
│           │                                                         │
│  collector (Rust, AF_PACKET SCTP/M3UA, host net, NET_RAW)          │
│           ↓  HTTP /metrics @ :9090                                  │
│  tui (Rust ratatui/crossterm, host net, TTY-attached)              │
└─────────────────────────────────────────────────────────────────────┘
```

**TUI ሲያስኪዱ በራስ-ሰር በኮንሶል ላይ ይታያል:**

```bash
# መንገድ 1 — ሙሉ ቁልል ከፊት (foreground)፣ TUI በራስ-ሰር በተርሚናል መጨረሻ ላይ ይያያዛል:
docker compose -f docker-compose.yml up

# መንገድ 2 — ጌትዌይ + ሰብሳቢ እንደ daemon፣ TUI ከፊት (foreground):
docker compose -f docker-compose.yml up -d ussdgw collector
docker compose -f docker-compose.yml up tui

# መንገድ 3 — ስክሪፕት ይጠቀሙ:
./scripts/03-start-gateway.sh --with-monitor
./scripts/03-start-gateway.sh --tui-only       # TUI ያያይዙ
```

ዳሽቦርዱ **በቦታው ላይ ነው የሚቀረጸው (in-place)፣ መስመር አያሸብልልም** ምክንያቱም
crossterm alternate-screen + ratatui dirty-cell redraw ይጠቀማል።

TUI በሚሰራበት ጊዜ:
- `q` / `Esc` — መውጫ
- `p` — ለአፍታ ማቆም/መቀጠል (pause/resume polling)
- `r` — ታሪክ ዳግም ማስጀመር (የ60ሰከንድ sparkline)

TUIን ኮንቴይነሩን ሳይገድሉ ይለዩ: `Ctrl-p Ctrl-q`
እንደገና ያያይዙ: `docker attach sctp-m3ua-tui`

ዝርዝሩን በ`bpf-tps-monitor/README.md` ይመልከቱ (የሰብሳቢ `/metrics` JSON ንድፍ፣
የ2 ኮንቴይነሮች ማብራሪያ፣ የ`NET_RAW` መስፈርት)።

---

## 🏷️ የስሪት አያያዝ (Versioning)

ጥቅሉ **Hybrid SemVer + CalVer** እቅድ ይጠቀማል: `<USSDGW_VERSION>+<BUILD_DATE>`

| መስክ | ምሳሌ | ዓላማ |
|---|---|---|
| `USSDGW_VERSION` | `7.3.1` | SemVer ዋና — የተረጋጋ፣ ለደንበኛ የሚቀርብ፣ ባህሪ/ጥገና ሲኖር ይጨምራል |
| `BUILD_DATE` | `20260628` | CalVer — የተገነባበት ቀን (UTC) |
| `BUILD_ID` | `20260628T052817-3d3881a` | ሙሉ ኦዲት መታወቂያ (ቀን + ሰዓት + git አጭር hash) |
| `USSDGW_VERSION_FULL` | `7.3.1+20260628` | የተዋሀደ (SemVer+CalVer) ለምዝግብ ማስታወሻ/ባነር |

**የDocker ምስል ያውርዱ (በgit ውስጥ የለም — በጣም ትልቅ ~700 MB):**

```bash
# ከአርቲፋክት አገልጋይ:
wget https://artifacts.digicom-et.com/ussdgw/docker/restcomm-ussd-zulu-7.3.1.tar -P docker/

# ወይም ከምንጭ ኮድ ይገንቡ:
cd ../ussdgateway/release-wildfly && ./build-docker-zulu.sh
```

**የSemVer ህጎች:**
- `PATCH` (7.3.1 → 7.3.2): የሳንካ ጥገና፣ ውቅር/API አይነካም
- `MINOR` (7.3.x → 7.4.0): አዲስ ባህሪ ወደኋላ ተኳዃኝ (backward-compat) — አዲስ endpoint መጨመር፣ አዲስ አጭር ኮድ መጨመር
- `MAJOR` (7.x → 8.0.0): ሰበሪ ለውጥ (breaking change) — Wildfly መተው፣ ወደብ መቀየር፣ የ/opt/ussdgw መዋቅር መቀየር

**ለደንበኛ የሚቀርበው Docker መለያ SemVer ይጠቀማል** (`restcomm-ussd-zulu:7.3.1`) — በበርካታ ድጋሚ ግንባታዎች የተረጋጋ።
**የውስጥ ልቀት-ተኮር መለያ** ሙሉውን ይጠቀማል (`restcomm-ussd-zulu:7.3.1-20260628-3d3881a`) — ለመመለሻ እና ኦዲት ያገለግላል።

የአሁኑን ስሪት ይመልከቱ:
```bash
./scripts/version.sh              # አንድ-መስመር
./scripts/version.sh --json       # ማሽን-ተነባቢ
./scripts/version.sh --all        # ዝርዝር
```

ከመገንባቱ በፊት ይሻሩ:
```bash
USSDGW_VERSION=7.4.0 ./scripts/build-package.sh
echo "7.4.0" > VERSION              # ወይም የVERSION ፋይል ያርትዑ
```

---

## 🛠️ ከምንጭ ኮድ መገንባት (Build from Source — ለገንቢ)

`build-all.sh`ን በመጠቀም ሙሉውን ፓይፕላይን ከGitHub ይገንቡ:

### መስፈርቶች
- git፣ mvn፣ ant፣ podman/docker
- Java 8 (Zulu) — በ`mise install java@zulu-8` ይጫኑ
- በግምት 5 GB ዲስክ

### WildFly clean
`wildfly-10.0.0.Final.zip` ከዚህ ያውርዱ:
https://download.jboss.org/wildfly/10.0.0.Final/wildfly-10.0.0.Final.zip
ይክፈቱ፣ ጥቅም የሌላቸውን ሞጁሎች ያስወግዱ፣ እንደ `resources/wildfly-10.0.0.Final-cleaned.zip` ያስቀምጡ።
ወይም ካለው የussdgateway ማከማቻ ይቅዱ:
```bash
cp ../ussdgateway/release-wildfly/wildfly-10.0.0.Final-cleaned.zip resources/
```

### Jolokia
የ`build-all.sh` ስክሪፕት jolokia-war 1.7.2 ከMaven Central በራስ-ሰር ያወርዳል።

### መገንባት
```bash
# ሙሉ ግንባታ: clone + Maven + Ant + Docker
./build-all.sh

# Clone መተው (ኮድ በአካባቢው አለ)
SKIP_CLONE=1 ./build-all.sh

# የDocker ምስል ብቻ መገንባት (zip አስቀድሞ አለ)
SKIP_CLONE=1 SKIP_MAVEN=1 ./build-all.sh

# የDocker ምስል ሳይፈጠር መገንባት
SKIP_DOCKER=1 ./build-all.sh
```

### የግንባታ ቅደም ተከተል
1. jain-slee (ዋናው የSLEE ማዕቀፍ)
2. jSS7 (የSS7 ፕሮቶኮል ቁልል)
3. sip-servlets (SIP servlet)
4. jain-slee.ss7 (SS7/MAP RA)
5. jain-slee.sip (SIP RA)
6. jain-slee-http-okhttp (HTTP RA)
7. ussdgateway (የUSSD Gateway መተግበሪያ)
8. Ant release → zip
9. የDocker ምስል (Zulu 8 JDK)

---

## የአገልጋይ መስፈርቶች

Docker፣ JDK 8፣ Python 3.9+፣ SCTP (`lsmod | grep sctp`)፣ RAM ≥ 6 GB።
BPF ሰብሳቢ/TUI `NET_RAW` ችሎታ (capability) ያስፈልገዋል (በcompose ውስጥ አስቀድሞ ተካቷል)።



---

## 🔬 ምርምር (Research)

የUSSD Gateway ፕሮዳክሽን ጥቅል የሚከተሉትን የምርምር ክፍሎች ያካትታል።
(The USSD Gateway production package includes the following research components.)

### 1. BPF/eBPF SCTP/M3UA TPS መቆጣጠሪያ (Monitor) — 2 Rust Tools

የSCTP/M3UA ሲግናሊንግ ፕሌን ላይ የእውነተኛ ጊዜ ፓኬት መቆጣጠሪያ ሲስተም። በRust የተጻፉ 2 መሣሪያዎችን ያካትታል።

| መሣሪያ (Tool) | ቋንቋ (Lang) | ሚና (Role) | ቴክኖሎጂ (Tech) |
|---|---|---|---|
| **collector** | Rust | Headless BPF ሰብሳቢ — የSGW ኢንተርፌስ ላይ ፓኬቶችን ይቆጣጠራል፣ SCTP/M3UA ፓኬቶችን በሰከንድ ይቆጥራል፣ በM3UA መልእክት ክፍል ይመድባል፣ JSON በ `:9090/metrics` ያቀርባል | AF_PACKET/BPF, Rust, CAP_NET_RAW + SYS_ADMIN |
| **tui** | Rust | በይነተገናኝ ተርሚናል ዳሽቦርድ — ሰብሳቢውን በየሰከንዱ ይጠይቃል፣ በቦታው ላይ የሚቀረጽ (flicker-free) ሙሉ ስክሪን ያሳያል | ratatui + crossterm, Rust |

**የቁልፍ ሰሌዳ ቁልፎች (Key bindings):**
- `q` / `Esc` — መውጫ (Quit)
- `p` — ለአፍታ ማቆም/መቀጠል (Pause/Resume)
- `r` — ታሪክ ዳግም ማስጀመር (Reset 60s sparkline history)

**ቦታ (Location):** `bpf-tps-monitor/` — `collector/` + `tui/` ንዑስ ማውጫዎች ያሉት
**መገንባት (Build):** `cargo build --release --target x86_64-unknown-linux-musl` → የማይንቀሳቀስ ባይነሪ ~3-5 MB

### 2. Mastra AI Multi-Agent QA ቡድን (Team)

በAI የተደገፈ ራስ-ሰር የሙከራ ስርዓት። Mastra ፍሬምወርክ በመጠቀም ብዙ AI ወኪሎችን ያስተባብራል።

| ክፍል (Component) | ብዛት (Count) | መግለጫ (Description) |
|---|---|---|
| **Agents** | 3 | Orchestrator (አስተባባሪ)፣ Code Analyzer (ኮድ ተንታኝ)፣ Test Executor (ሙከራ አስፈጻሚ) |
| **Workflows** | 2 | test-pipeline (TRIGGER→ANALYZE→EXECUTE→EVALUATE)፣ scenario-runner (S0-S10 ደረጃ በደረጃ በtmux መስኮቶች) |
| **Tools** | 7 | map-runner፣ http-runner፣ grpc-runner፣ docker-manager፣ tmux-session-manager፣ pcap-capture፣ pcap-utils |

- **ቦታ (Location):** `ussd-qa-team/mastra/`
- **ፍሬምወርክ (Framework):** Mastra v1.17 + @mastra/core v1.48
- **ሞዴል (Model):** GPT-4o (OpenAI)
- **ስቱዲዮ (Studio):** Web UI በ `http://localhost:4111`

### 3. Virtual Session Bridge — ምናባዊ ክፍለ-ጊዜ ድልድይ

የUSSD Gateway ዋና ባህሪ — ቀርፋፋ የመተግበሪያ አገልጋይ (AS) ምላሽ በሚዘገይበት ጊዜ የMAP ውይይት መረጋጋትን ይጠብቃል።

| ዘዴ (Mechanism) | ዓላማ (Purpose) |
|---|---|
| **Adaptive Gate (EWMA)** | በየ `networkId` አማካይ የAS መዘግየት → ተለዋዋጭ በር በ `[1000 ms, 7000 ms]` ክልል ውስጥ |
| **Virtual Session Bridge** | በሩ ሲያልፍ S1 MAP ውይይትን ይለቃል፣ ምናባዊ ክፍለ-ጊዜ በመሸጎጫ ያስቀምጣል፣ ውጤቱን በNI push S2 ያቀርባል |
| **Unified Reconciliation** | Channel A (ተመሳሳይ gRPC/HTTP ግንኙነት) ወይም Channel B (`POST /restcomm` + `X-Ussd-Request-Id`) በኩል የዘገየ AS ምላሽን ያዛምዳል |
| **Bridge TTL** | 180 ሰከንድ የመሸጎጫ ቆይታ — AS ለመመለስ ያለው መስኮት |

**የጊዜ ገደብ ተዋረድ (Timeout hierarchy):**
```
1000 ms ≤ adaptiveGate ≤ 7000 ms (asyncGateTimeoutMs) < 60000 ms (dialogTimeout) < 90000 ms (TCAP)
```

ዝርዝር ዲዛይን፡ [`docs/design/virtual-session-bridge.md`](docs/design/virtual-session-bridge.md)



---

## 🚀 እንዴት ማስኪደት (How to Run)

### ፈጣን ጅምር (Quick Start) — አንድ አገልጋይ፣ Docker

```bash
cd /opt/ussdgw-prod-release
sudo modprobe sctp
chmod +x scripts/*.sh

# 1. አካባቢ አረጋግጥ (Verify environment)
./scripts/00-preflight.sh

# 2. Docker ምስል ጫን (Load image)
./scripts/01-load-docker-image.sh

# 3. አስተናጋጅ አዋቅር (Setup host)
sudo ./scripts/02-setup-host.sh

# 4. ጌትዌይ አስነሳ (Start gateway)
./scripts/03-start-gateway.sh
curl -fs http://localhost:8080/jolokia/version && echo " OK"
```

### E2E gRPC ሙከራ (E2E gRPC Test)

```bash
# Terminal 1: ጌትዌይ + gRPC AS
./scripts/03-start-gateway.sh
./scripts/05-start-grpc-as.sh

# Terminal 2: MAP ማጨስ ሙከራ (10 ውይይቶች *100#)
./scripts/06-run-map-smoke.sh

# Terminal 3: gRPC በቀጥታ ሙከራ
./scripts/07-run-grpc-smoke.sh

# ሁሉንም አቁም (Stop all)
./scripts/stop-all.sh
```

### ከBPF መቆጣጠሪያ ጋር (With BPF Monitor)

```bash
# ጌትዌይ + ሰብሳቢ እንደ daemon፣ TUI ከፊት (foreground)
docker compose -f docker-compose.yml up -d ussdgw collector
docker compose -f docker-compose.yml up tui

# ወይም ስክሪፕቶችን ተጠቀም (Or use scripts):
./scripts/03-start-gateway.sh --with-monitor    # ጌትዌይ + ሰብሳቢ
./scripts/03-start-gateway.sh --tui-only        # TUI ዳሽቦርድ አያይዝ
```

### ከMastra AI QA ጋር (With Mastra AI QA)

```bash
cd ussd-qa-team/mastra
export NVM_DIR="$HOME/.config/nvm" && . "$NVM_DIR/nvm.sh"

# ጥገኛዎችን ጫን (Install dependencies)
npm install

# የአካባቢ ተለዋዋጮችን አዋቅር (Configure env)
# .env ፋይል አርትዕ: OPENAI_API_KEY=sk-... (PKG_ROOT auto-detected, tool paths optional)

# Mastra Studio አስነሳ (Start Studio)
npx mastra dev
# → Web UI በ http://localhost:4111 ይከፈታል

# የሙከራ ፓይፕላይን አስኪድ (Run test pipeline)
# በStudio Web UI ወይም በAPI:
curl -X POST http://localhost:4111/api/workflows/test-pipeline/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"trigger": "manual", "message": "E2E smoke test"}}'

# Scenario runner — ደረጃ በደረጃ በtmux መስኮቶች (per-step in tmux windows)
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S0","S1","S2","S3","S4","S5"], "pcap": true}}'

# የtmux መስኮቶችን ተመልከት (View tmux windows)
tmux attach -t ussd-e2e-test
# Ctrl-b 0-9 → በመስኮቶች መካከል መቀያየር (switch between windows)
# Ctrl-b d  → መለየት (detach)
```

### ሙሉ ላብ (Full Lab) — ሁሉም መሣሪያዎች በtmux

```bash
# Terminal 1: ጌትዌይ + ሰብሳቢ
cd /opt/ussdgw-prod-release
./scripts/03-start-gateway.sh --with-monitor

# Terminal 2: BPF TUI ዳሽቦርድ
docker compose -f docker-compose.yml up tui

# Terminal 3: gRPC AS
./scripts/05-start-grpc-as.sh
tail -f grpc-as.log

# Terminal 4: MAP ማጨስ ሙከራ
./scripts/06-run-map-smoke.sh

# Terminal 5: gRPC ሙከራ
./scripts/07-run-grpc-smoke.sh

# Terminal 6: HTTP Pull + Push
./scripts/09-start-http-as.sh
./scripts/12-run-http-pull-smoke.sh
./scripts/13-run-http-push-smoke.sh

# ወይም Mastra scenario-runner ተጠቀም — ሁሉንም በራስ-ሰር በtmux መስኮቶች ያስኪዳል
# (Or use Mastra scenario-runner — auto-spawns all in tmux windows)
npx mastra run scenario-runner --scenarios S0,S1,S2,S3,S4,S5,S6,S7,S8,S9,S10 --pcap
```

### የፓኬት ቀረጻ (PCAP Capture) በሙከራ ጊዜ

```bash
# ከMastra tool በኩል (Via Mastra tool)
# scenario-runner ሲጀምር --pcap ባንዲራ ሲሰጠው በራስ-ሰር tcpdump ያስነሳና ያቆማል

# በእጅ (Manual):
sudo tcpdump -i any -s 0 -w /tmp/ussd-e2e.pcap proto 132 &
# ... ሙከራዎችን አስኪድ (run tests) ...
sudo pkill tcpdump
capinfos /tmp/ussd-e2e.pcap
wireshark /tmp/ussd-e2e.pcap &
```

