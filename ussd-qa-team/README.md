# USSD QA Team — AI-Powered Multi-Agent Testing 🤖

> **የUSSD Gateway በAI የተደገፈ የጥራት ማረጋገጫ ቡድን (AI-Powered QA Team)**
> 
> Mastra multi-agent system ለUSSD Gateway ራስ-ሰር ሙከራ (automated testing) እና ተንተና (analysis)።

---

## 🔬 ምርምር (Research)

### 1. Mastra Framework

| ክፍል | ስሪት | ማብራሪያ |
|---|---|---|
| `mastra` | v1.17 | Mastra CLI + Studio — AI agent orchestration framework |
| `@mastra/core` | v1.48 | ዋና ላይብረሪ — agents, workflows, tools, LLM integration |
| `zod` | v3.25 | TypeScript-first schema validation |
| Node.js | ≥22 | Runtime |

- **Studio Web UI:** `http://localhost:4111` — ወኪሎችን ለመሞከር፣ workflows ለማስኪደት፣ graphs ለማየት (test agents, run workflows, view graphs)
- **LLM:** GPT-4o (OpenAI) — ወኪሎች ራሳቸው እንዲያስቡ እና መሣሪያዎችን እንዲመርጡ ያስችላል

### 2. Agent Architecture (የወኪል ሥነ-ሕንፃ)

```
                    ┌─────────────────┐
                    │  Orchestrator   │  ← ማስተባበሪያ (Coordination)
                    │  (GPT-4o)       │     ትሪገሮችን ይቀበላል (manual/webhook/schedule)
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌────────────┐
     │   Code     │  │   Test     │  │  Scenario  │
     │  Analyzer  │  │  Executor  │  │   Runner   │
     │  (GPT-4o)  │  │  (GPT-4o)  │  │ (workflow) │
     └────────────┘  └─────┬──────┘  └────────────┘
                           │
                    ┌──────┼──────┬──────────┬──────────┐
                    ▼      ▼      ▼          ▼          ▼
                 map-   http-   grpc-     docker-    pcap-
                runner  runner  runner    manager   capture
```

| ወኪል (Agent) | ሚና (Role) | መሣሪያዎች (Tools) |
|---|---|---|
| **Orchestrator** | ሙሉ ፓይፕላይን ያስተባብራል፣ ትሪገሮችን ይቀበላል፣ የትኞቹን ሙከራዎች ማስኪደት እንዳለበት ይወስናል | (ሌሎች ወኪሎችን ያስተዳድራል) |
| **Code Analyzer** | Git diff በመተንተን የተነኩትን የፕሮቶኮል ንብርቦች (MAP/SS7፣ HTTP፣ gRPC፣ Session) እና የአደጋ ደረጃ ይለያል | — |
| **Test Executor** | ሙከራዎችን በማስኪደት ውጤቶችን፣ TPS፣ መዘግየቶችን ይሰበስባል | mapRunner, httpRunner, grpcRunner, dockerManager |

### 3. Tools Research (የመሣሪያዎች ምርምር)

| መሣሪያ (Tool) | ዓይነት (Type) | ማብራሪያ (Description) |
|---|---|---|
| **map-runner** | Java wrapper | MAP/SS7 ሎድ ሙከራ — `java -cp lib/* Client` — SCTP→M3UA→SCCP→TCAP→MAP |
| **http-runner** | Java wrapper | HTTP ሎድ ጄነሬተር — `java ...UssdHttpLoadGenerator` |
| **grpc-runner** | Shell wrapper | gRPC AS ማጨስ ሙከራ — `bash 05-start-grpc-as.sh` |
| **docker-manager** | Docker compose | ጌትዌይ ኮንቴይነር — up/down/logs/status/restart |
| **tmux-session-manager** | Tmux | tmux ክፍለ-ጊዜ አስተዳደር — ለእያንዳንዱ መሣሪያ የተለየ መስኮት ይፈጥራል፣ የቀጥታ ሎግ ታይታ |
| **pcap-capture** | tcpdump | የኔትወርክ ፓኬት ቀረጻ — start/stop/status፣ SCTP/TCP ማጣሪያ |
| **pcap-utils** | Utility | PCAP ፋይል ትንተና — ስታቲስቲክስ, capinfos መጠቅለያ |

### 4. Workflows (የስራ ፍሰቶች)

#### test-pipeline (የሙከራ ፓይፕላይን)

```
TRIGGER → ANALYZE (git diff) → EXECUTE (parallel tests) → EVALUATE (verdict)
```

- **TRIGGER:** ምልክት ይቀበላል (manual/webhook/schedule)፤ webhook ከሆነ git diff ያገኛል
- **ANALYZE:** Git diff በመተንተን የተነኩትን ንብርቦች ይለያል (MAP፣ HTTP፣ gRPC፣ Session Mgmt)
- **EXECUTE:** የተመከሩትን ሙከራዎች በትይዩ ያስኪዳል
- **EVALUATE:** PASS/FAIL/SKIPPED በመቁጠር ብይን ይሰጣል + የተዋቀረ ሪፖርት

#### scenario-runner (የሁኔታ አስኪዳጅ)

```
S0 → S1 → S2 → S3 → S4 → S5 → S6 → S7 → S8 → S9 → S10
 │     │     │     │     │     │     │     │     │     │     │
 ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼     ▼
[pre-  [load  [setup [start [start [map  [grpc [grpc [http [http [stop
flight] docker] host] gw]   grpc] smoke]smoke]push] pull] push] all]
```

እያንዳንዱ ደረጃ በተለየ tmux መስኮት ውስጥ ይሰራል። ደረጃ ከማለፉ በፊት የጤና ማረጋገጫ ያደርጋል። ሲጨርስ tmux ክፍለ-ጊዜውን ክፍት ይተወዋል ለምርመራ።

### 5. Rust BPF Monitor Integration

ከ `../../bpf-tps-monitor/` ጋር ውህደት፡

| አገልግሎት | ሚና |
|---|---|
| **collector** | BPF/AF_PACKET SCTP/M3UA ፓኬት መቆጣጠሪያ → `/metrics` JSON በ `:9090` |
| **tui** | ratatui ተርሚናል ዳሽቦርድ — ሰብሳቢውን በየሰከንዱ ይጠይቃል |

---

## 🚀 እንዴት ማስኪደት (How to Run)

### ቅድመ-ሁኔታዎች (Prerequisites)

- Node.js ≥ 22
- npm
- OpenAI API key
- Docker (ለጌትዌይ ሙከራ)
- tmux (ለscenario-runner — `sudo apt-get install tmux`)
- tcpdump (ለpcap-capture — `sudo apt-get install tcpdump`)

### ጭነት (Installation)

```bash
cd ussdgw-prod-release/ussd-qa-team/mastra
export NVM_DIR="$HOME/.config/nvm" && . "$NVM_DIR/nvm.sh"

# ጥገኛዎችን ጫን
npm install

# .env አዋቅር
# አርትዕ: OPENAI_API_KEY=sk-...
# እና የUSSDGW መንገዶችን አስተካክል
nano .env
```

### Mastra Studio አስነሳ (Start Studio)

```bash
npx mastra dev
# → http://localhost:4111 ይከፈታል
```

በStudio ውስጥ:
- **Agents tab:** ወኪሎችን በቀጥታ አነጋግሩ (chat with agents)
- **Workflows tab:** ፓይፕላይን አስኪዱ፣ ግራፍ ይመልከቱ
- **Tools tab:** መሣሪያዎችን ሞክሩ

### test-pipeline አስኪድ (Run Test Pipeline)

```bash
# በAPI በኩል
curl -X POST http://localhost:4111/api/workflows/test-pipeline/start \
  -H "Content-Type: application/json" \
  -d '{
    "inputData": {
      "trigger": "manual",
      "message": "E2E smoke test after config change"
    }
  }'

# ምላሽ (Response):
# {
#   "verdict": "PASS",  // or FAIL, WARNING
#   "report": "=== USSD QA TEAM TEST REPORT === ...",
#   "summary": "3P/0F/2S — WARNING"
# }
```

### scenario-runner አስኪድ (Run Scenario Runner)

```bash
# ሁሉንም ሁኔታዎች ከፓኬት ቀረጻ ጋር አስኪድ
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{
    "inputData": {
      "scenarios": ["S0", "S1", "S2", "S3", "S4", "S5", "S6"],
      "pcap": true,
      "pkgRoot": "/opt/ussdgw-prod-release"
    }
  }'

# የተወሰኑ ሁኔታዎች ብቻ (Specific scenarios only):
curl -X POST http://localhost:4111/api/workflows/scenario-runner/start \
  -H "Content-Type: application/json" \
  -d '{"inputData": {"scenarios": ["S3", "S4", "S5"], "pcap": false}}'

# የtmux መስኮቶችን ተመልከት
tmux attach -t ussd-e2e-test
# Ctrl-b 0-9 → በመስኮቶች መካከል መቀያየር
# Ctrl-b d   → መለየት (detach ነገር ግን መስኮቶቹ መስራታቸውን ይቀጥላሉ)
```

### በቀጥታ ከMastra CLI (Direct CLI)

```bash
# የተወሰነ ሁኔታ አስኪድ
npx mastra run scenario-runner --scenario S3

# የሙከራ ፓይፕላይን አስኪድ
npx mastra run test-pipeline --trigger manual --message "Smoke test"

# ወኪል አነጋግር (Chat with agent)
npx mastra chat orchestrator "Run MAP smoke test and report"
```

### የተለያዩ ሁኔታዎች (Scenarios Reference)

| ኮድ | ስም | ማብራሪያ | ትዕዛዝ |
|---|---|---|---|
| S0 | preflight | አካባቢ አረጋግጥ | `lsmod \| grep sctp`, `java -version`, `docker info` |
| S1 | load-docker | Docker ምስል ጫን | `./scripts/01-load-docker-image.sh` |
| S2 | setup-host | አስተናጋጅ አዋቅር | `sudo ./scripts/02-setup-host.sh` |
| S3 | start-gateway | ጌትዌይ አስነሳ | `docker compose up -d` + health check `:8080/jolokia/version` |
| S4 | start-grpc-as | gRPC AS አስነሳ | `ussd_as_server.py --port 8443` |
| S5 | map-smoke | MAP ማጨስ ሙከራ | `java ...Client ... *100# BALANCE` (10 ውይይቶች) |
| S6 | grpc-smoke | gRPC ማጨስ ሙከራ | `loadtest_client.py --multi-menu` |
| S7 | grpc-push | gRPC Push ሙከራ | `grpc_push_client.py :8453` |
| S8 | http-pull | HTTP Pull ሙከራ | `http_as_server.py :8049` + MAP `*519#` |
| S9 | http-push | HTTP Push ሙከራ | `http_push_loadtest.py` |
| S10 | stop-all | ሁሉንም አቁም | kill AS PID + `docker compose down` + `tmux kill-session` |

### PCAP ቀረጻ (Packet Capture)

```bash
# ከMastra pcap-capture tool በኩል (በscenario-runner ውስጥ በራስ-ሰር)
# ወይም በእጅ (manual):
sudo tcpdump -i any -s 0 -w /tmp/ussd-e2e-map.pcap proto 132 &
# MAP ሙከራ አስኪድ ...
sudo pkill tcpdump

# ውጤት ተንትን (Analyze):
capinfos /tmp/ussd-e2e-map.pcap
# Number of packets: 1234
# Capture duration: 45.3 seconds

wireshark /tmp/ussd-e2e-map.pcap &
```

---

## 📁 የፕሮጀክት መዋቅር (Project Structure)

```
ussd-qa-team/
├── README.md                          ← ይህ ፋይል (this file)
└── mastra/
    ├── package.json                   # Mastra v1.17 + @mastra/core v1.48
    ├── tsconfig.json                  # TypeScript config
    ├── .env                           # OPENAI_API_KEY + USSDGW paths
    ├── HOW-TO-RUN.md                  # ተጨማሪ ማስኪያ መመሪያ (additional run guide)
    └── src/mastra/
        ├── index.ts                   # Mastra instance — agents + workflows registration
        ├── agents/
        │   ├── orchestrator.ts        # አስተባባሪ ወኪል — ፓይፕላይን ማስተባበሪያ
        │   ├── code-analyzer.ts       # ኮድ ተንታኝ — git diff → impacted layers
        │   └── test-executor.ts       # ሙከራ አስፈጻሚ — 7 መሣሪያዎች
        ├── workflows/
        │   ├── test-pipeline.ts       # TRIGGER→ANALYZE→EXECUTE→EVALUATE
        │   └── scenario-runner.ts     # S0-S10 per-step execution in tmux
        └── tools/
            ├── map-runner.ts          # MAP/SS7 load test wrapper
            ├── http-runner.ts         # HTTP load test wrapper
            ├── grpc-runner.ts         # gRPC smoke test wrapper
            ├── docker-manager.ts      # Docker compose management
            ├── tmux-session-manager.ts # Tmux session/window management
            ├── pcap-capture.ts        # tcpdump packet capture
            └── pcap-utils.ts          # PCAP analysis utilities
```

---

## 🔗 ተዛማጅ ሰነዶች (Related Documents)

| ሰነድ | ይዘት |
|---|---|
| [../README.md](../README.md) | ዋና የፕሮዳክሽን ጥቅል README |
| [../docs/e2e-grpc-ussd-test_en.md](../docs/e2e-grpc-ussd-test_en.md) | E2E ሙከራ መመሪያ (EN) |
| [../docs/design/virtual-session-bridge.md](../docs/design/virtual-session-bridge.md) | Virtual Session Bridge ዲዛይን |
| [../bpf-tps-monitor/README.md](../bpf-tps-monitor/README.md) | BPF SCTP/M3UA TPS Monitor |
| [mastra/HOW-TO-RUN.md](mastra/HOW-TO-RUN.md) | Mastra ዝርዝር ማስኪያ መመሪያ |

---

*የመጨረሻ ማሻሻያ (Last updated): 2026-07-01 — Mastra multi-agent QA team, scenario-runner workflow, pcap-capture tool, tmux integration.*
