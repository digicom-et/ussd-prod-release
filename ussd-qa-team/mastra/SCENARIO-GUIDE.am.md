# USSD Gateway — የE2E ሁኔታ ሙከራ መመሪያ (Scenario Test Guide)

**ስሪት (Version):** 1.0
**የታለመላቸው (Audience):** QA መሐንዲሶች፣ DevOps፣ የውህደት ሞካሪዎች (Integration Testers)
**ስፋት (Scope):** 11 ሁኔታዎች (S0–S10) — ቅድመ-ማረጋገጫ፣ Docker ምስል ጫን፣ አስተናጋጅ ማዋቀር፣ ጌትዌይ ማስነሳት፣ አራቱም የፕሮቶኮል መንገዶች (MAP/gRPC/HTTP Pull/HTTP Push) እና ንጹህ ማቆም።

> **ማስታወሻ (Note):** ይህ መመሪያ የተጻፈው በአማርኛ+English ቅይጥ ስልት ነው። ቴክኒካል ትዕዛዞችና ቃላት በEnglish ይቀራሉ፤ ማብራሪያዎች በአማርኛ ይቀርባሉ።

---

## ዝርዝር ማውጫ (Table of Contents)

1. [የሥነ-ሕንፃ ንድፍ](#-የሥነ-ሕንፃ-ንድፍ-architecture-diagram)
2. [ፈጣን ማጣቀሻ ሰንጠረዥ](#-ፈጣን-ማጣቀሻ-ሰንጠረዥ-quick-reference-table)
3. [ሁሉንም ሁኔታዎች እንዴት ማስኪደት እንደሚቻል](#-ሁሉንም-ሁኔታዎች-እንዴት-ማስኪደት-እንደሚቻል-how-to-run-all)
4. [የቀጥታ ሎግ እይታ እና Tmux](#-የቀጥታ-ሎግ-እይታ-እና-tmux)
5. [PCAP ፓኬት ቀረጻ](#-pcap-ፓኬት-ቀረጻ-pcap-capture)
6. [የሁኔታ ዝርዝሮች (S0–S10)](#-የሁኔታ-ዝርዝሮች-s0s10)
7. [የችግር መፍታት ማውጫ](#-የችግር-መፍታት-ማውጫ-troubleshooting-index)

---

## 🏗️ የሥነ-ሕንፃ ንድፍ (Architecture Diagram)

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

**የፕሮቶኮል ፍሰት ማጠቃለያ (Protocol flow summary):**

| መንገድ (Path)     | መግቢያ (Ingress)   | መውጫ (Egress)      | የሙከራ ሁኔታ |
|-------------------|--------------------|---------------------|------------|
| MAP → gRPC        | SCTP :8011/12      | gRPC :8443          | S5         |
| gRPC በቀጥታ (direct)| —                 | gRPC :8443          | S6         |
| gRPC Push (NI)    | gRPC :8453         | Gateway → ተጠቃሚ     | S7         |
| HTTP Pull         | SCTP + HTTP        | HTTP :8049          | S8         |
| HTTP Push         | HTTP :8080          | Gateway → ተጠቃሚ     | S9         |

---

## 📊 ፈጣን ማጣቀሻ ሰንጠረዥ (Quick Reference Table)

| #   | ስም (Name)         | Tmux መስኮት                    | ሎግ ፋይል (Log File(s))                                                     | ጊዜ (Duration) | ጥገኝነት (Depends) |
|-----|---------------------|-------------------------------|----------------------------------------------------------------------------|----------------|-------------------|
| S0  | Preflight           | *(sync — በቀጥታ)*               | —                                                                          | ~10 ሰከንድ      | —                 |
| S1  | Load Docker         | *(sync — በቀጥታ)*               | —                                                                          | 30ሰከ – 2 ደቂቃ   | S0                |
| S2  | Setup Host          | *(sync — በቀጥታ)*               | —                                                                          | ~5 ሰከንድ       | S1                |

## 🚀 ሁሉንም ሁኔታዎች እንዴት ማስኪደት እንደሚቻል (How to Run All)

### አማራጭ ሀ — በMastra በኩል (የሚመከር / Recommended)

Mastra ሁሉንም ሁኔታዎች በራስ-ሰር በtmux መስኮቶች ያስኪዳል።

```bash
cd /opt/ussdgw-prod-release/ussd-qa-team/mastra

# Mastra dev አገልጋይ ያስነሱ
export NVM_DIR="$HOME/.config/nvm" && . "$NVM_DIR/nvm.sh"
npx mastra dev

# → Web UI በ http://localhost:4111 ይከፈታል
# → ይሂዱ: Workflows → scenario-runner → Start

# ወይም በcurl በኩል:
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S0","S1","S2","S3","S4","S5"], "pcap": true}}'
```

**የMastra payload ማጣቀሻ (Reference):**

```json
{
  "scenarios": ["S0","S1","S2","S3","S4","S5","S6","S7","S8","S9","S10"],
  "pcap": true
}
```

- `scenarios` — የሚፈጸሙት የሁኔታ መታወቂያዎች በቅደም ተከተል።
- `pcap` — `true` ከሆነ፣ Mastra ከS5 በፊት `tcpdump` ያስነሳና ከS9 በኋላ ያቆማል።

### አማራጭ ለ — በስክሪፕቶች በኩል (Via Individual Scripts)

እያንዳንዱን ሁኔታ በተናጠል ማስኪደት ከፈለጉ:

```bash
export PKG_ROOT=/opt/ussdgw-prod-release

# S0 — ቅድመ-ማረጋገጫ
lsmod | grep sctp && java -version && python3 --version && docker info

# S1 — Docker ምስል ጫን
cd $PKG_ROOT && bash scripts/01-load-docker-image.sh

# S2 — አስተናጋጅ አዋቅር
sudo bash $PKG_ROOT/scripts/02-setup-host.sh

# S3 — ጌትዌይ አስነሳ (+ BPF monitor አማራጭ)
$PKG_ROOT/scripts/03-start-gateway.sh --with-monitor

# S4 — gRPC AS አስነሳ
$PKG_ROOT/scripts/05-start-grpc-as.sh

# S5 — MAP ማጨስ ሙከራ
$PKG_ROOT/scripts/06-run-map-smoke.sh

# S6 — gRPC ማጨስ ሙከራ
$PKG_ROOT/scripts/07-run-grpc-smoke.sh

# S7 — gRPC Push ሙከራ
$PKG_ROOT/scripts/14-run-grpc-push-smoke.sh

# S8 — HTTP Pull ሙከራ
$PKG_ROOT/scripts/09-start-http-as.sh
$PKG_ROOT/scripts/12-run-http-pull-smoke.sh

# S9 — HTTP Push ሙከራ
$PKG_ROOT/scripts/13-run-http-push-smoke.sh

# S10 — ሁሉንም አቁም
$PKG_ROOT/scripts/stop-all.sh
```

### አማራጭ ሐ — ሙሉ ላብራቶሪ በአንድ ጊዜ

```bash
sudo /opt/ussdgw-prod-release/scripts/start-all.sh
```

---

| S3  | Start Gateway       | `docker-gw`                   | `/tmp/ussd-logs/docker-gw.log`                                             | 3–5 ደቂቃ        | S2                |
| S4  | Start gRPC AS       | `grpc-as`                     | `/tmp/ussd-logs/grpc-as.log`                                               | ~10 ሰከንድ      | S3                |
| S5  | MAP Smoke           | `map-smoke`                   | `/tmp/ussd-logs/map-smoke.log`                                             | 30ሰከ – 2 ደቂቃ   | S3 + S4           |
| S6  | gRPC Smoke          | `grpc-smoke`                  | `/tmp/ussd-logs/grpc-smoke.log`                                            | ~40 ሰከንድ      | S4                |
| S7  | gRPC Push           | `grpc-push`                   | `/tmp/ussd-logs/grpc-push.log`                                             | ~40 ሰከንድ      | S3                |
| S8  | HTTP Pull           | `http-as` + `http-pull`       | `/tmp/ussd-logs/http-as.log`፣ `/tmp/ussd-logs/http-pull.log`                | 1–2 ደቂቃ        | S3                |
| S9  | HTTP Push           | `http-push`                   | `/tmp/ussd-logs/http-push.log`                                             | ~40 ሰከንድ      | S3                |
| S10 | Stop All            | *(sync — በቀጥታ)*               | —                                                                          | ~10 ሰከንድ      | —                 |

---

## 📺 የቀጥታ ሎግ እይታ እና Tmux

የሙከራ ስርዓቱ **`ussd-e2e-test`** የተባለ tmux session ይፈጥራል። እያንዳንዱ አገልግሎት የራሱ መስኮት (window) አለው:

```bash
# ከtmux session ጋር ይገናኙ
tmux attach -t ussd-e2e-test

# በtmux ውስጥ:
#   Ctrl-b 0-9  → በመስኮቶች መካከል መቀያየር (docker-gw, grpc-as, map-smoke, ...)
#   Ctrl-b d    → መለየት (detach — ሁሉም መስራታቸውን ይቀጥላሉ)
#   Ctrl-b [    → ማሸብለል ሁነታ (scroll mode — ቀስቶች/PgUp/PgDn; q ለመውጣት)

# ሁሉንም መስኮቶች ይዘርዝሩ
tmux list-windows -t ussd-e2e-test
```

### ያለ tmux ሎጎችን መከታተል (Tail Logs Without Tmux)

```bash
tail -f /tmp/ussd-logs/docker-gw.log
tail -f /tmp/ussd-logs/map-smoke.log
tail -f /tmp/ussd-logs/grpc-smoke.log
tail -f /tmp/ussd-logs/http-as.log
tail -f /tmp/ussd-logs/http-pull.log
tail -f /tmp/ussd-logs/http-push.log
tail -f /tmp/ussd-logs/grpc-push.log
```

### ሁሉንም ሎጎች በአንድ ጊዜ (Multitail)

```bash
# ካልተጫነ: sudo apt install multitail
multitail /tmp/ussd-logs/*.log
```

---

## 📦 PCAP ፓኬት ቀረጻ (PCAP Capture)

በሙከራ ጊዜ የSCTP (proto 132) እና gRPC (TCP port 8443/8453) ትራፊክ ይቅረጹ:

```bash
# ከS5 (MAP Smoke) በፊት ቀረጻ ይጀምሩ:
sudo tcpdump -i any -s 0 -w /tmp/ussd-e2e.pcap \
  '(proto 132) or (tcp port 8443) or (tcp port 8453) or (tcp port 8049)' &

# Mastra pcap: true ሲያስተዳድረው ፋይሉ የሚቀመጠው:
# /tmp/ussd-logs/ussd-e2e.pcap

# ቀረጻ ያቁሙ:
sudo pkill tcpdump

# ቀረጻውን ይፈትሹ:
capinfos /tmp/ussd-e2e.pcap
wireshark /tmp/ussd-e2e.pcap &
```

**የSCTP ልዩ Wireshark ማጣሪያዎች (SCTP-specific filters):**

```
sctp.verification_tag           → የSCTP association መጀመሪያ ያግኙ
m3ua.protocol_data.opcode == 1  → የMAP መልእክቶች
sccp.message_type == 0x09       → UDT (connectionless SCCP)
```

---

## 📋 የሁኔታ ዝርዝሮች (S0–S10)

---

### S0 — PREFLIGHT (ቅድመ-ማረጋገጫ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | ማንኛውም የማሰማራት እርምጃ ከመጀመሩ በፊት ሁሉም የአካባቢ ቅድመ-ሁኔታዎች መሟላታቸውን ያረጋግጡ። |
| **ጥገኝነት (Depends)**| ምንም የለም (None — የመጀመሪያ እርምጃ)። |
| **ጊዜ (Duration)**    | ~10 ሰከንድ። |
| **Tmux መስኮት**       | *(sync — በቀጥታ፣ tmux አይጠቀምም)* |
| **ሎግ ፋይል**           | stdout ብቻ (ዘላቂ ሎግ የለም)። |

**በእጅ ትዕዛዝ (Manual Command):**

```bash
echo "=== S0: Preflight ===" \
  && echo -n "SCTP module:   " && (lsmod | grep sctp > /dev/null && echo "PASS" || echo "FAIL (የጎደለ)") \
  && echo -n "Java runtime:  " && (java -version 2>&1 | head -1) \
  && echo -n "Python3:       " && python3 --version \
  && echo -n "Docker daemon: " && (docker info > /dev/null 2>&1 && echo "PASS" || echo "FAIL (አልተነሳም)") \
  && echo "=== Preflight complete ==="
```

**Mastra ትዕዛዝ:**

### S1 — LOAD DOCKER IMAGE (የDocker ምስል ጫን)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | የRestComm USSD Gateway Docker ምስል ከልቀት ጥቅል ውስጥ ማስመጣት (import)። |
| **ጥገኝነት (Depends)**| S0 ማለፍ አለበት (Docker እየሰራ መሆን አለበት)። |
| **ጊዜ (Duration)**    | 30 ሰከንድ – 2 ደቂቃ (በተለምዶ ~700 MB .tar ፋይል)። |
| **Tmux መስኮት**       | *(sync — በቀጥታ)* |
| **ሎግ ፋይል**           | stdout ብቻ። |

**በእጅ ትዕዛዝ (Manual Command):**

```bash
cd /opt/ussdgw-prod-release && bash scripts/01-load-docker-image.sh
```

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S1"]}
```

**የሚጠበቀው ውጤት:** ስክሪፕቱ `docker load -i docker/restcomm-ussd-*.tar` ያስኪዳል። በstderr ላይ ምንም ስህተት አይኖርም።

**የጤና ማረጋገጫ (Health Check):**

```bash
docker images restcomm-ussd --format "{{.Repository}}:{{.Tag}}"
# የሚጠበቀው: restcomm-ussd:7.3.x (ወይም ተመሳሳይ የስሪት መለያ)
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| `No such file: docker/restcomm-ussd-*.tar` | የtar ፋይል ጎደለ | በ`PKG_ROOT` ስር ያለውን `docker/` ማውጫ ያረጋግጡ |
| `Cannot connect to Docker daemon` | Docker አልተነሳም | `sudo systemctl start docker` |
| `no space left on device` | ዲስክ ሞልቷል | `df -h /var/lib/docker` |
| `Error: image already exists` | ከዚህ በፊት ተጭኗል | ችላ ማለት ይቻላል፤ ምስሉ በመሸጎጫ ውስጥ አለ |

---

### S2 — SETUP HOST (አስተናጋጅ አዋቅር)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | የ`/opt/ussdgw` ማውጫ ዛፍ መፍጠር እና ነባሪ ውቅር መዝራት (የራውቲንግ ህጎች፣ የSCTP associations)። |
| **ጥገኝነት (Depends)**| S1 መጠናቀቅ አለበት። |
| **ጊዜ (Duration)**    | ~5 ሰከንድ። |
| **Tmux መስኮት**       | *(sync — በቀጥታ)* |
| **ሎግ ፋይል**           | stdout ብቻ። |

**በእጅ ትዕዛዝ (Manual Command):**

```bash
sudo bash /opt/ussdgw-prod-release/scripts/02-setup-host.sh
```

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S2"]}
```

**የሚጠበቀው ውጤት:** ስክሪፕቱ በጸጥታ ይጠናቀቃል። ምንም ስህተት አይኖርም።

**የጤና ማረጋገጫ (Health Check):**

```bash
ls -la /opt/ussdgw/data/UssdManagement_scroutingrule.xml
# የሚጠበቀው: ፋይሉ በቅርብ ጊዜ ማህተም መኖሩን ያረጋግጡ
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| `Permission denied` | ስክሪፕቱ root ያስፈልገዋል | `sudo` በመጠቀም ያስኪዱ |
| ማውጫው አስቀድሞ አለ | ቀዳሚ ሩጫ ውሂብ ትቷል | ችላ ይበሉ፤ ስክሪፕቱ idempotent ነው |
| `02-setup-host.sh: No such file` | `PKG_ROOT` ትክክል አይደለም | `export PKG_ROOT=/opt/ussdgw-prod-release` |

---


```json
{"scenarios": ["S0"]}
```

**የሚጠበቀው ውጤት (Expected Output):**

```
=== S0: Preflight ===
SCTP module:   PASS
Java runtime:  openjdk version "1.8.0_xxx" ... (ወይም 11.0.x)
Python3:       Python 3.x.x
Docker daemon: PASS
=== Preflight complete ===
```


### S3 — START GATEWAY (ጌትዌይ አስነሳ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | USSD Gatewayን በDocker Compose በኩል ማስነሳት እና WildFly ጤናማ እስኪሆን መጠበቅ። |
| **ጥገኝነት (Depends)**| S2 (የአስተናጋጅ ማዋቀር ከራውቲንግ ህጎች ጋር)። |
| **ጊዜ (Duration)**    | 3–5 ደቂቃ (የመጀመሪያ ማስነሳት — WildFly ቡት + SCTP stack init)። |
| **Tmux መስኮት**       | `docker-gw` |
| **ሎግ ፋይል**           | `/tmp/ussd-logs/docker-gw.log` |

**በእጅ ትዕዛዝ (Manual — ከtmux ጋር):**

```bash
mkdir -p /tmp/ussd-logs
tmux new-session -d -s ussd-e2e-test -n docker-gw \
  "docker compose -f /opt/ussdgw-prod-release/gateway/docker-compose.yml up 2>&1 | tee /tmp/ussd-logs/docker-gw.log"
```

**በእጅ ትዕዛዝ (ያለ tmux — foreground):**

```bash
cd /opt/ussdgw-prod-release/gateway && docker compose up -d
```

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S3"]}
```

**የሚጠበቀው ውጤት:** WildFly ሙሉ በሙሉ ይቡታል። ሎጉ ያሳያል:
- `WildFly Full ... started in ...`
- `SCTP stack initialized`
- `Jolokia: Agent started`

**የጤና ማረጋገጫ (Health Check):**

```bash
curl -fs http://localhost:8080/jolokia/version
# የሚጠበቀው: HTTP 200 + JSON {"timestamp":...,"value":{"version":"..."},"status":200}
```

**የጥበቃ ስልት (Wait Strategy):** Jolokiaን በየ10ሰከንዱ እስከ 5 ደቂቃ ይጠይቁ:

```bash
for i in $(seq 1 30); do
  curl -fs http://localhost:8080/jolokia/version > /dev/null 2>&1 && echo "Gateway ዝግጁ ነው!" && break
  echo "በመጠበቅ ላይ... ($i/30)"
  sleep 10
done
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| ፖርት 8080 ከ5 ደቂቃ በኋላ ምላሽ አይሰጥም | WildFly አሁንም እየቡተ ነው ወይም ወድቋል | `docker logs ussd-prod` ወይም `tail -100 /tmp/ussd-logs/docker-gw.log` |
| `Address already in use` :8080/8011/8012 | ቀዳሚ instance አሁንም እየሰራ ነው | `docker compose -f /opt/ussdgw-prod-release/gateway/docker-compose.yml down` |
| `modprobe: FATAL: Module sctp not found` | SCTP kernel module ጎደለ | `sudo modprobe sctp && lsmod \| grep sctp` |
| `No route to host` ለSCTP peer | ፋየርዎል SCTP እያገደ ነው | `sudo iptables -L -n \| grep 8011` |
| Docker compose አልተገኘም | `docker-compose` vs `docker compose` | `docker-compose` (በሰረዝ) ይሞክሩ |

---

### S4 — START gRPC AS (gRPC AS አስነሳ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | የUSSD ምናሌ አመክንዮ የሚያስተናግደውን የPython gRPC Application Server ማስነሳት። |
| **ጥገኝነት (Depends)**| S3 (ጌትዌይ ጤናማ — AS ራሱን ችሎ ነው ግን S5 ሁለቱንም ያስፈልገዋል)። |
| **ጊዜ (Duration)**    | ~10 ሰከንድ። |
| **Tmux መስኮት**       | `grpc-as` |
| **ሎግ ፋይል**           | `/tmp/ussd-logs/grpc-as.log` |

**በእጅ ትዕዛዝ (Manual Command):**

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

**ከtmux ጋር (background):**

```bash
mkdir -p /tmp/ussd-logs
tmux new-window -t ussd-e2e-test -n grpc-as \
  "cd /opt/ussdgw-prod-release/tools/grpc-as-tester && .venv/bin/python ussd_as_server.py --port 8443 --min-delay 1 --max-delay 100 --menu-config menu_config.json 2>&1 | tee /tmp/ussd-logs/grpc-as.log"
```

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S4"]}
```

**የሚጠበቀው ውጤት:**

```
USSD gRPC AS listening on :8443
Loaded menu config: menu_config.json
Profiles: BALANCE, ENQUIRY, ...
```

**የጤና ማረጋገጫ (Health Check):**

```bash
grep "listening on :8443" /tmp/ussd-logs/grpc-as.log

### S5 — MAP SMOKE (MAP ማጨስ ሙከራ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | ከጫፍ-እስከ-ጫፍ (E2E) የSS7 MAP USSD ሙከራ: MAP client → SCTP → Gateway → gRPC AS → Gateway → MAP ምላሽ። የ`*100#` አጭር ኮድ እና BALANCE መገለጫ በመጠቀም ሙሉውን MAP/gRPC ቧንቧ ያረጋግጣል። |
| **ጥገኝነት (Depends)**| S3 (ጌትዌይ ጤናማ) + S4 (gRPC AS በ:8443 ላይ እያዳመጠ)። |
| **ጊዜ (Duration)**    | 30 ሰከንድ – 2 ደቂቃ (የመጀመሪያ ሩጫ ~20ሰከ SCTP INIT handshake ያካትታል)። |
| **Tmux መስኮት**       | `map-smoke` |
| **ሎግ ፋይል**           | `/tmp/ussd-logs/map-smoke.log` |

**በእጅ ትዕዛዝ (Manual Command):**

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

**የመለኪያ ማብራሪያ (Parameter breakdown):**

| መለኪያ | ትርጉም | ዋጋ |
|---|---|---|
| `10` | ጠቅላላ ውይይቶች (USSD sessions) | 10 |
| `5` | በትይዩ የሚሰሩ ክሮች (concurrent threads) | 5 |
| `sctp 127.0.0.1 8011 -1 127.0.0.1 8012 IPSP` | SCTP አካባቢ/ሩቅ ማሰር | Local:8011, Remote:8012, IPSP client mode |
| `101 102 1 2 3 2` | M3UA routing context + አውታረመረብ መለኪያዎች | መደበኛ የሙከራ ዋጋዎች |
| `8 6 8 1111112 9960639999` | GT + MSISDN አድራሻ | IMSI:1111112, MSISDN:9960639999 |
| `1 4 -100 0` | SCCP አድራሻ + SSN | SSN=4 (HLR)፣ GT ትርጉም |
| `"*100#" BALANCE 50 200` | USSD ሕብረቁምፊ + መገለጫ + መዘግየቶች | *100# አጭር ኮድ፣ BALANCE ምናሌ |

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S5"]}
```

**የሚጠበቀው ውጤት (Expected Output — ቁልፍ መስመሮች):**

```
Starting association with peer: 127.0.0.1:8012
AS1 state changed to: ACTIVE
AS1 is now ACTIVE!
...
Total completed dialogs = 10
FailedScenario  = 0
```

**የጤና ማረጋገጫ (Health Check):**

```bash
grep -E "AS1 is now ACTIVE" /tmp/ussd-logs/map-smoke.log
grep "Total completed dialogs" /tmp/ussd-logs/map-smoke.log
grep "FailedScenario" /tmp/ussd-logs/map-smoke.log
# "FailedScenario = 0" ማለፍ ለተሳካ ሙከራ ያስፈልጋል
```

**የስኬት መስፈርቶች (Success Criteria):** ሦስቱም እውነት መሆን አለባቸው:
1. `AS1 is now ACTIVE!` በሎግ ውስጥ ይታያል
2. `Total completed dialogs = 10`
3. `FailedScenario = 0`

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| `AS1 not ACTIVE after 30s` | SCTP association አልተመሰረተም | SCTP module ያረጋግጡ: `lsmod \| grep sctp`፤ የጌትዌይ ሎጎችን ይፈትሹ |
| `java.lang.ClassNotFoundException` | የjSS7 ቤተ-መጻህፍት በ`lib/` ውስጥ ጎድለዋል | `mvn dependency:copy-dependencies` በtools/jss7-map-load ያስኪዱ |
| `Not valid short code: *100#` | የራውቲንግ ህግ ጎደለ | `/opt/ussdgw/data/UssdManagement_scroutingrule.xml` ያርትዑ፣ `*100#` → gRPC ይጨምሩ፣ S2 እንደገና ያስነሱ |
| `Connection refused: 127.0.0.1:8011` | Gateway SCTP አያዳምጥም | የdocker-gw ሎግ ለ`SCTP stack initialized` ይፈትሹ |
| `gRPC deadline exceeded` | gRPC AS ምላሽ አይሰጥም | S4 ያረጋግጡ: `grep "listening on :8443" /tmp/ussd-logs/grpc-as.log` |
| `FailedScenario > 0` | አንዳንድ ውይይቶች ወድቀዋል | በmap-smoke.log ውስጥ የእያንዳንዱን ውይይት ስህተት ይፈትሹ |

---

# ተዛማጅ መስመር መመለስ አለበት።
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| `Address already in use` :8443 | ቀዳሚ instance አሁንም እየሰራ ነው | `pkill -f ussd_as_server.py` ከዛ እንደገና ይሞክሩ |
| `No module named 'grpcio'` | venv አልተዋቀረም | `cd tools/grpc-as-tester && .venv/bin/pip install -r requirements.txt` |
| `menu_config.json: No such file` | የተሳሳተ የስራ ማውጫ | ሁልጊዜ መጀመሪያ `cd tools/grpc-as-tester` ያድርጉ |
| Python ስሪት < 3.8 | የቆየ Python | `python3 --version`; 3.9+ ይጫኑ |

---

**የጤና ማረጋገጫ (Health Check):** አራቱም መስመሮች `PASS` ወይም ትክክለኛ የስሪት ሕብረቁምፊ ማሳየት አለባቸው። ማንኛውም `FAIL` ተጨማሪ ሂደት ያግዳል።

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| `SCTP module: FAIL` | sctp kernel module አልተጫነም | `sudo modprobe sctp` |
| `Java runtime:` ስህተት | JRE/JDK የለም ወይም የተሳሳተ ስሪት | `sudo apt install openjdk-8-jre-headless` |
| `Docker daemon: FAIL` | Docker አልተነሳም | `sudo systemctl start docker` |
| `python3: not found` | Python 3 አልተጫነም | `sudo apt install python3` |

---



### S6 — gRPC SMOKE (gRPC ማጨስ ሙከራ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | የgRPC Application Serverን በቀጥታ የጭነት ሙከራ ማድረግ (SS7/gatewayን ሳያልፍ)። AS በትይዩ የgRPC ምናሌ ክፍለ-ጊዜዎችን ማስተናገድ መቻሉን ያረጋግጣል። |
| **ጥገኝነት (Depends)**| S4 (gRPC AS በ:8443 ላይ እየሰራ)። Gateway አያስፈልግም። |
| **ጊዜ (Duration)**    | ~40 ሰከንድ (30ሰከ የሙከራ ቆይታ + ማስነሳት)። |
| **Tmux መስኮት**       | `grpc-smoke` |
| **ሎግ ፋይል**           | `/tmp/ussd-logs/grpc-smoke.log` |

**በእጅ ትዕዛዝ (Manual Command):**

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

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S6"]}
```

**የሚጠበቀው ውጤት:**

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

**የጤና ማረጋገጫ (Health Check):**

```bash
grep -E "completed:" /tmp/ussd-logs/grpc-smoke.log
grep "errors: 0" /tmp/ussd-logs/grpc-smoke.log
# ሁለቱም መመሳሰል አለባቸው፤ errors 0 መሆን አለበት
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| `Connection refused` | gRPC AS አልተነሳም | S4 ያረጋግጡ: `grep "listening on :8443" /tmp/ussd-logs/grpc-as.log` |
| `achieved TPS` ከ50 በጣም ያነሰ | ሲስተም ከመጠን ተጭኗል ወይም ከፍተኛ መዘግየት | `--tps` ወደ 20 ይቀንሱ፤ CPU በ`htop` ይፈትሹ |
| `errors > 0` | AS ስህተቶች መለሰ | በgrpc-smoke.log ውስጥ ለgRPC status codes ይፈትሹ |
| `ModuleNotFoundError: grpc` | venv አልነቃም | `cd tools/grpc-as-tester && .venv/bin/pip install -r requirements.txt` |

---

### S7 — gRPC PUSH (gRPC ግፊት ሙከራ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | የgRPC Network-Initiated (NI) Push መንገድ ማረጋገጥ: ውጫዊ ደንበኛ የUSSD push ጥያቄዎችን ወደ gateway gRPC Push endpoint ይልካል፣ እሱም ወደሚመሰሉ ተጠቃሚዎች ያደርሳል። |
| **ጥገኝነት (Depends)**| S3 (gateway ከgRPC Push ጋር በፖርት 8453 መስራት አለበት)። |
| **ጊዜ (Duration)**    | ~40 ሰከንድ። |
| **Tmux መስኮት**       | `grpc-push` |
| **ሎግ ፋይል**           | `/tmp/ussd-logs/grpc-push.log` |

**ቅድመ-ሁኔታ (Prerequisite) — gRPC Push በgateway web mgmt console ላይ ያንቁ:**

1. `http://localhost:9990` በብራውዘር ይክፈቱ (WildFly management console)።
2. **Server Settings** → **gRPC Push** ይሂዱ።
3. **GrpcPushServerEnabled** = `true` ያድርጉ።
4. **Port** = `8453` ያድርጉ።
5. **Save** ይጫኑና ያረጋግጡ።

**በእጅ ትዕዛዝ (Manual Command):**

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

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S7"]}
```

**የሚጠበቀው ውጤት (Expected Output — ቁልፍ መስመሮች):**

```
mode: multi

### S8 — HTTP PULL (HTTP መሳብ ሙከራ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | በHTTP Pull መንገድ የE2E ሙከራ: MAP client → SCTP → Gateway → HTTP AS → Gateway → MAP ምላሽ። ይህ ወደ HTTP Pull Application Server የሚዞረውን `*519#` አጭር ኮድ ይጠቀማል። |
| **ጥገኝነት (Depends)**| S3 (gateway ጤናማ)። gRPC AS አያስፈልግም ነገር ግን HTTP AS እየሰራ መሆን አለበት። |
| **ጊዜ (Duration)**    | 1–2 ደቂቃ። |
| **Tmux መስኮቶች**     | `http-as` + `http-pull` |
| **ሎግ ፋይሎች**         | `/tmp/ussd-logs/http-as.log`፣ `/tmp/ussd-logs/http-pull.log` |

**ይህ ሁኔታ ሁለት ተርሚናሎችን (ወይም ሁለት tmux መስኮቶችን) ይፈልጋል:**

#### ተርሚናል 1 — HTTP AS አገልጋይ

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

#### ተርሚናል 2 — MAP ሙከራ በHTTP Pull ላይ

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

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S8"]}
```

**የሚጠበቀው ውጤት:**

- **http-as.log:** `HTTP AS listening on :8049`፣ ከgateway የሚመጡ የHTTP ጥያቄዎች።
- **http-pull.log:** `AS1 is now ACTIVE!`፣ `Total completed dialogs = 10`፣ `FailedScenario = 0`።

**የጤና ማረጋገጫ (Health Check):**

```bash
# HTTP AS እየሰራ መሆኑን ያረጋግጡ
grep "listening on :8049" /tmp/ussd-logs/http-as.log

# MAP ሙከራ ማለፉን ያረጋግጡ
grep "FailedScenario = 0" /tmp/ussd-logs/http-pull.log
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| HTTP AS `Address already in use` :8049 | ቀዳሚ instance | `pkill -f http_as_server.py` |
| `*519#` ራውቲንግ አይሰራም | የHTTP scrule ግቤት ጎደለ | `*519#` → HTTP Pull በ`UssdManagement_scroutingrule.xml` ውስጥ ይጨምሩ |
| Gateway HTTP 500 ይመልሳል | HTTP AS በፍጥነት ምላሽ አይሰጥም | `--max-delay` ይጨምሩ ወይም የAS ሎጎችን ይፈትሹ |
| MAP `Connection refused` :8011 | Gateway SCTP አያስኪድም | S3 በJolokia በኩል ጤናማ መሆኑን ያረጋግጡ |

---

### S9 — HTTP PUSH (HTTP ግፊት ሙከራ)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | የHTTP Network-Initiated Push endpoint የጭነት ሙከራ: ውጫዊ ደንበኛ የUSSD push ጥያቄዎችን በHTTP በኩል ወደ gateway REST API ይልካል፣ እሱም ወደሚመሰሉ UEዎች ያደርሳል። |
| **ጥገኝነት (Depends)**| S3 (gateway እየሰራ፣ HTTP REST endpoint በ:8080)። |
| **ጊዜ (Duration)**    | ~40 ሰከንድ። |
| **Tmux መስኮት**       | `http-push` |
| **ሎግ ፋይል**           | `/tmp/ussd-logs/http-push.log` |

**በእጅ ትዕዛዝ (Manual Command):**

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

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S9"]}
```

**የሚጠበቀው ውጤት:**

```
mode: multi
profile: BALANCE
target: http://127.0.0.1:8080/restcomm
target TPS: 50
duration: 30s
...
### S10 — STOP ALL (ሁሉንም አቁም)

| ባህሪ (Attribute)    | ዋጋ (Value) |
|-----------------------|-------------|
| **ዓላማ (Purpose)**    | ሁሉንም እየሰሩ ያሉ አገልግሎቶች፣ የDocker ኮንቴይነሮች እና tmux session በስርዓት ማቆም (graceful shutdown)። |
| **ጥገኝነት (Depends)**| ከS3–S9 ማንኛቸውም ወይም ሁሉም እየሰሩ ሊሆኑ ይችላሉ። |
| **ጊዜ (Duration)**    | ~10 ሰከንድ። |
| **Tmux መስኮት**       | *(sync — tmux session ይገደላል ወይም ለምርመራ ክፍት ይቀራል)* |
| **ሎግ ፋይል**           | — |

**በእጅ ትዕዛዝ (Manual Command):**

```bash
# የPython ሂደቶችን ይግደሉ
pkill -f ussd_as_server.py
pkill -f http_as_server.py
pkill -f loadtest_client.py
pkill -f grpc_push_client.py
pkill -f http_push_loadtest.py

# የDocker ኮንቴይነሮችን ያቁሙ
cd /opt/ussdgw-prod-release/gateway && docker compose down

# የtmux session ይግደሉ (አማራጭ — Mastra ለምርመራ ክፍት ይተወዋል)
# tmux kill-session -t ussd-e2e-test

echo "ሁሉም አገልግሎቶች ቆመዋል። (All services stopped.)"
```

**Mastra ትዕዛዝ:**

```json
{"scenarios": ["S10"]}
```

**የሚጠበቀው ውጤት:** ሁሉም Python ሂደቶች ተቋርጠዋል፣ `docker compose down` ተጠናቋል።

**የጤና ማረጋገጫ (Health Check):**

```bash
# ምንም gateway ኮንቴይነሮች አይኖሩም
docker ps --filter "name=ussd-prod" --format "{{.Names}}" | wc -l
# የሚጠበቀው: 0

# ምንም Python የሙከራ አገልጋዮች አይኖሩም
pgrep -af "ussd_as_server\|http_as_server\|loadtest_client\|grpc_push_client\|http_push_loadtest"
# የሚጠበቀው: ምንም ውጤት አይኖርም
```

**ማስታወሻ (Note):** የtmux session `ussd-e2e-test` ከMastra workflow በኋላ ሆን ተብሎ ክፍት ይቀራል ሎጎችን ለመመርመር። በእጅ ይዝጉት:

```bash
tmux kill-session -t ussd-e2e-test
```

**ችግር መፍታት (Troubleshooting):**

| ምልክት (Symptom) | መንስኤ (Cause) | መፍትሔ (Fix) |
|---|---|---|
| Docker ኮንቴይነር አይቆምም | ኮንቴይነሩ ተንጠልጥሏል (hung) | `docker kill ussd-prod` ከዛ `docker compose down` |
| `pkill` አይዛመድም | የሂደት ስም ይለያያል | `ps aux \| grep -E "as_server\|loadtest"` ትክክለኛውን ስም ለማግኘት |
| ፖርቶች ከማቆም በኋላም ተይዘዋል | Zombie ሂደቶች | `sudo lsof -i :8443,8049,8011,8012,8080` እና `kill -9 <PID>` |

---

## 🔧 የችግር መፍታት ማውጫ (Troubleshooting Index)

በበርካታ ሁኔታዎች ላይ ለሚከሰቱ ችግሮች ፈጣን ማጣቀሻ:

| ምድብ (Category) | ምልክት (Symptom) | ይፈትሹ (Check) |
|---|---|---|
| **SCTP** | Association በጭራሽ ACTIVE አይሆንም | `lsmod \| grep sctp`፣ `sudo modprobe sctp` |
| **Docker** | ኮንቴይነር ወዲያውኑ ይወጣል | `docker logs ussd-prod` ለstack trace |
| **ፖርቶች (Ports)** | `Address already in use` | `sudo ss -tlnp \| grep -E "8011\|8012\|8080\|8443\|8453\|8049"` |
| **gRPC** | Deadline exceeded | AS ተደራሽ ነው? `nc -zv localhost 8443` |
| **ራውቲንግ (Routing)** | አጭር ኮድ አይታወቅም | `cat /opt/ussdgw/data/UssdManagement_scroutingrule.xml \| grep "*100#"` |
| **ማህደረ-ትውስታ (Memory)** | Java OOM በdocker-gw.log | Docker ማህደረ-ትውስታ ይጨምሩ: `docker update --memory 4g ussd-prod` |
| **ዲስክ (Disk)** | ሎጎች ዲስክ እየሞሉ ነው | `du -sh /tmp/ussd-logs/`፣ በ`rm -rf /tmp/ussd-logs/*.log` ያጽዱ |
| **Mastra** | Workflow ተንጠልጥሏል | የMastra ሎጎችን ይፈትሹ: `~/.mastra/logs/` |
| **PCAP** | tcpdump SCTP አይቀርጽም | SCTP proto 132 ነው፣ ለlocalhost SCTP `-i lo` ይጠቀሙ |

---

## 🌐 የወደቦች ማጣቀሻ (Port Reference)

| ወደብ (Port) | አገልግሎት (Service) | ሁኔታ (Scenario) |
|---|---|---|
| 8011 | MAP Client (Java) | S5፣ S8 |
| 8012 | SCTP Gateway | S3፣ S5፣ S8 |
| 8080 | HTTP REST + Jolokia (`/jolokia/version`) | S3፣ S9 |
| 8443 | gRPC AS (Pull MO) | S4፣ S5፣ S6 |
| 8453 | gRPC Push (NI) | S7 |
| 8049 | HTTP Pull AS | S8 |
| 9090 | BPF Monitor metrics (`/metrics`) | S3 (--with-monitor) |
| 9990 | WildFly Management Console | S7 (gRPC Push ማንቃት) |
| 4111 | Mastra Studio (AI QA) | Mastra |

---

## 📁 የሎግ ፋይሎች ማጠቃለያ (Log Files Summary)

ሁሉም ሎጎች በ`/tmp/ussd-logs/` ስር ይቀመጣሉ:

| ሎግ ፋይል | ሁኔታ | ይዘት |
|---|---|---|
| `docker-gw.log` | S3 | የWildFly ቡት፣ SCTP stack init፣ Jolokia |
| `grpc-as.log` | S4 | gRPC AS ማዳመጥ ጀምሯል፣ የገቢ ጥያቄዎች |
| `map-smoke.log` | S5 | SCTP association፣ MAP ውይይቶች፣ ውጤቶች |
| `grpc-smoke.log` | S6 | gRPC የጭነት ሙከራ መለኪያዎች (TPS፣ errors) |
| `grpc-push.log` | S7 | gRPC Push የጭነት ሙከራ መለኪያዎች |
| `http-as.log` | S8 | HTTP AS ማዳመጥ ጀምሯል፣ የገቢ HTTP ጥያቄዎች |
| `http-pull.log` | S8 | MAP ሙከራ በHTTP Pull በኩል |
| `http-push.log` | S9 | HTTP Push የጭነት ሙከራ መለኪያዎች |

---

## 🧪 ሙሉ ላብራቶሪ ማስኪደት (Full Lab — All Tools)

ሁሉንም መሣሪያዎች በተለያዩ ተርሚናሎች ማስኪደት:

```bash
# Terminal 1: ጌትዌይ + BPF ሰብሳቢ
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

# Terminal 6: HTTP Pull + HTTP Push
./scripts/09-start-http-as.sh
./scripts/12-run-http-pull-smoke.sh
./scripts/13-run-http-push-smoke.sh

# Terminal 7: gRPC Push (ከማንቃት በኋላ በ:9990)
./scripts/14-run-grpc-push-smoke.sh

# Terminal 8: ሁሉንም አቁም
./scripts/stop-all.sh
```

**ወይም Mastra scenario-runner ይጠቀሙ:**

```bash
cd /opt/ussdgw-prod-release/ussd-qa-team/mastra
npx mastra run scenario-runner --scenarios S0,S1,S2,S3,S4,S5,S6,S7,S8,S9,S10 --pcap
```

---

## 📝 የስሪት ታሪክ (Version History)

| ቀን (Date)   | ስሪት (Version) | ለውጦች (Changes) |
|--------------|----------------|-------------------|
| 2025-07-01   | 1.0            | የመጀመሪያ ልቀት: 11 ሁኔታዎች (S0–S10) — ቅድመ-ማረጋገጫ፣ Docker ማሰማራት፣ ጌትዌይ ማስነሳት፣ MAP/gRPC/HTTP Pull/HTTP Push፣ እና ማቆምን የሚሸፍኑ። |

---

*ለ USSD Gateway E2E QA ቡድን የተዘጋጀ። ከMastra scenario-runner workflow ጋር በጋራ ይቀመጣል።*

> **ማስታወሻ (Note):** ይህ ሰነድ የተጻፈው በአማርኛ+English ቅይጥ ስልት ነው። ሙሉ የEnglish ስሪት ለማግኘት [`SCENARIO-GUIDE.en.md`](SCENARIO-GUIDE.en.md) ይመልከቱ። የቬትናምኛ ስሪት ለማግኘት [`SCENARIO-GUIDE.vi.md`](SCENARIO-GUIDE.vi.md) ይመልከቱ።
