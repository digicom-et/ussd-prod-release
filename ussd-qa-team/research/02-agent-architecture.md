# Agent Architecture — USSD QA Team

> **Date:** 30/06/2026
> **Framework choice:** LangGraph (primary) + Sandbox (hardness tests)

---

## 1. Kiến trúc tổng thể

```
                          ┌─────────────────────────────────┐
                          │      HUMAN OPERATOR              │
                          │   (Approve destructive tests)    │
                          └──────────┬──────────────────────┘
                                     │
┌────────────────────────────────────┼──────────────────────────────────┐
│                        ORCHESTRATOR (LangGraph)                       │
│  ┌─────────────────────────────────────────────────────────────────┐ │
│  │                    Stateful Test Pipeline                        │ │
│  │  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐          │ │
│  │  │TRIGGER│→  │ANALYZE│→  │GENERATE│→ │EXECUTE│→  │EVALUATE│         │ │
│  │  └──────┘   └──────┘   └──────┘   └──────┘   └──────┘          │ │
│  │       ↑                                              │          │ │
│  │       └──────────── LOOP ENGINEER ◄──────────────────┘          │ │
│  └─────────────────────────────────────────────────────────────────┘ │
│                                                                       │
│  ┌─────────────────────┐  ┌─────────────────────┐                    │
│  │  HARDNESS ENGINEER  │  │   TEST EXECUTOR     │                    │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │                    │
│  │  │ Edge Case Gen │  │  │  │ MAP Runner    │  │                    │
│  │  │ Chaos Injector│  │  │  │ HTTP Runner   │  │                    │
│  │  │ Mutation Gen  │  │  │  │ gRPC Runner   │  │                    │
│  │  │ Boundary Gen  │  │  │  │ Docker Mgr    │  │                    │
│  │  └───────────────┘  │  │  │ Metrics Coll. │  │                    │
│  └─────────────────────┘  │  └───────────────┘  │                    │
│                           └─────────────────────┘                    │
│                                                                       │
│  ┌─────────────────────┐  ┌─────────────────────┐                    │
│  │   CODE ANALYZER     │  │    LOG ANALYZER      │                    │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │                    │
│  │  │ Git Diff      │  │  │  │ Pattern Match │  │                    │
│  │  │ AST Parser    │  │  │  │ Anomaly Det.  │  │                    │
│  │  │ Impact Map    │  │  │  │ Root Cause    │  │                    │
│  │  └───────────────┘  │  │  └───────────────┘  │                    │
│  └─────────────────────┘  └─────────────────────┘                    │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 2. Vai trò từng Agent

### 2.1 Orchestrator (Brain)

**Nhiệm vụ:** Điều phối toàn bộ pipeline test

| State | Input | Output | Action |
|---|---|---|---|
| TRIGGER | Git webhook / schedule / manual | Git diff | Nhận trigger, xác định scope test |
| ANALYZE | Git diff | Impact analysis + test plan | Gọi Code Analyzer để hiểu change impact |
| GENERATE | Impact analysis | Test scenarios | Gọi Hardness Engineer sinh test case |
| EXECUTE | Test scenarios | Raw results | Gọi Test Executor chạy test |
| EVALUATE | Raw results | Pass/Fail + Insights | Gọi Loop Engineer phân tích |

**Tech stack:** LangGraph StateGraph với typed state, conditional edges

### 2.2 Hardness Engineer

**Nhiệm vụ:** Sinh edge cases, boundary tests, chaos scenarios, mutation tests

**Tool set:**
- `edge_case_generator`: Từ protocol spec + code diff → sinh edge case
- `chaos_injector`: Inject network delay, packet loss, SCTP disconnection
- `boundary_tester`: Test tại các ngưỡng: max sessions, max TPS, timeout boundaries
- `mutation_tester`: Đột biến USSD string, MAP parameters, TCAP fields

**Safety:** Tất cả destructive tests phải chạy trong sandbox Docker isolated

→ Chi tiết: [03-hardness-engineer.md](./03-hardness-engineer.md)

### 2.3 Loop Engineer

**Nhiệm vụ:** Continuous feedback: analyze → suggest → verify → measure delta

**Workflow:**
```
Results → Analyze failures → Generate hypothesis → Propose fix/improvement
    → Verify (re-run) → Measure delta → Update knowledge base → Next iteration
```

**Tool set:**
- `result_analyzer`: So sánh expected vs actual, phân loại failure
- `regression_detector`: Phát hiện regression từ historical baseline
- `improvement_suggester`: Đề xuất code fix hoặc config tuning
- `delta_measurer`: Đo lường improvement giữa các runs

→ Chi tiết: [04-loop-engineer.md](./04-loop-engineer.md)

### 2.4 Test Executor

**Nhiệm vụ:** Chạy test tools và thu thập kết quả

| Tool | Protocol | Command |
|---|---|---|
| `map_runner` | MAP/SS7 | `java -cp lib/* Client ...` |
| `http_runner` | HTTP | `java ...UssdHttpLoadGenerator` |
| `grpc_runner` | gRPC | `python3 ussd_as_server.py` |
| `docker_mgr` | Docker | `docker compose up/down/logs` |
| `metrics_collector` | JMX | `curl http://.../jolokia/` |

### 2.5 Code Analyzer

**Nhiệm vụ:** Phân tích code changes để xác định impact

- Parse Git diff → identify changed files
- Map changed files → protocol layers affected (SCTP, M3UA, SCCP, TCAP, MAP, HTTP, gRPC)
- Map protocol layers → relevant test scenarios

**Ví dụ:**
```
Change: AdaptiveTimeoutManager.java
→ Layer: Session Management
→ Affected: timeout behavior, late response handling
→ Tests to run: timeout boundary tests, late response reconciliation
```

### 2.6 Log Analyzer

**Nhiệm vụ:** Phân tích logs để phát hiện anomaly

- Pattern matching: memory leak, dialog leak, timer leak, deadlock
- Anomaly detection: TPS drop, latency spike, error rate increase
- Root cause analysis: correlate log patterns → known issues

---

## 3. Communication Pattern

```
                  ┌──────────────────┐
                  │   BLACKBOARD     │
                  │  (Shared State)  │
                  └──┬───────────┬───┘
           ┌────────┘           └────────┐
           ▼                              ▼
   ┌──────────────┐              ┌──────────────┐
   │  Agent A     │              │  Agent B     │
   │  writes:     │              │  reads:      │
   │  results.json│              │  results.json│
   └──────────────┘              └──────────────┘
```

Tất cả agents giao tiếp qua **shared state** (JSON artifacts trong results folder), không direct call. Pattern này:
- Cho phép audit trail đầy đủ
- Dễ debug (mỗi step có artifact riêng)
- Cho phép resume từ checkpoint

---

## 4. State Management

### LangGraph State Schema

```python
from typing import TypedDict, List, Optional
from enum import Enum

class TestPhase(Enum):
    TRIGGER = "trigger"
    ANALYZE = "analyze"
    GENERATE = "generate"
    EXECUTE = "execute"
    EVALUATE = "evaluate"
    COMPLETE = "complete"

class OrchesatorState(TypedDict):
    phase: TestPhase
    git_diff: Optional[str]
    changed_files: List[str]
    impacted_layers: List[str]
    test_scenarios: List[dict]
    test_results: List[dict]
    analysis_report: Optional[str]
    loop_count: int
    max_loops: int
    approved_destructive: bool
```

---

## 5. Safety & Guardrails

| Guardrail | Mechanism |
|---|---|
| **No production impact** | All tests in isolated Docker network |
| **Rate limiting** | Max TPS per test run enforced |
| **SCTP safety** | Never send to production SCTP endpoints |
| **Human approval** | Destructive/chaos tests require human sign-off |
| **Timeout** | Each agent step has max timeout |
| **Rollback** | Docker compose down, restore backup config |

---

## 6. Deployment

```yaml
# docker-compose.qa-team.yml
services:
  orchestrator:
    build: ./agents/orchestrator
    volumes:
      - ./results:/results
      - ./configs:/configs

  hardness-engineer:
    build: ./agents/hardness-engineer
    network_mode: "none"  # Isolated!

  test-executor:
    build: ./agents/test-executor
    privileged: true  # For SCTP
    network_mode: "host"
```
