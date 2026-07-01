# Test Scenarios Mapping — USSD QA Team

> **Date:** 30/06/2026
> **Source:** Existing test infrastructure + Supermemory context

---

## 1. Existing Test Scenarios (from ussdgw-test & ussd-loadtest)

### 1.1 E2E Smoke Tests

| ID | Name | Protocol | Script | Duration |
|---|---|---|---|---|
| E2E-01 | gRPC AS startup | gRPC | `05-start-grpc-as.sh` | 5s |
| E2E-02 | MAP smoke (*100#) | MAP | `06-run-map-smoke.sh` | 10s |
| E2E-03 | gRPC load smoke | gRPC | `07-run-grpc-smoke.sh` | 30s |
| E2E-04 | gRPC push smoke | gRPC | `14-run-grpc-push-smoke.sh` | 10s |
| E2E-05 | Full deploy + rollback | All | `start-all.sh` / `03-switch-gateway.sh --rollback` | 120s |

### 1.2 Load Test Levels (AT-G1 → AT-P2)

| Level | TPS | Concurrent | Name | Duration |
|---|---|---|---|---|
| L1 | 1,000 | 5,000 | Smoke | 60s |
| L2 | 5,000 | 25,000 | Functional load | 120s |
| L3 | 10,000 | 50,000 | Standard load | 300s |
| L4 | 25,000 | 75,000 | Stress test | 300s |
| L5 | 50,000 | 100,000 | Extreme stress | 600s |

### 1.3 MAP-Level Specific Scenarios

| ID | Scenario | Command Example |
|---|---|---|
| MAP-01 | Basic USSD request/response | `Client ... "*100#"` |
| MAP-02 | Multi-step USSD dialog | `Client ... "*100*1*2#"` |
| MAP-03 | Concurrent dialog stress | `MAXCONCURRENTDIALOGS=50000` |
| MAP-04 | SCTP multi-homing failover | Multi-IP config |

---

## 2. AI-Generated Test Scenarios (Target)

### 2.1 Auto-generated từ Code Changes

| Trigger | Generated Scenarios |
|---|---|
| Change in `AdaptiveTimeoutManager.java` | Timeout boundary (EWMA oscillation), late response handling, race condition timeout/response |
| Change in `SctpAssociationManager.java` | SCTP connect/disconnect/reconnect, multi-homing failover, association breakdown mid-dialog |
| Change in `VirtualSessionBridge.java` | Bridge TTL boundary, late push, zombie session cleanup |
| Change in `MapDialogStateMachine.java` | All state transitions, invalid sequence, TCAP abort handling |
| Change in any config file | Config boundary tests, mutation tests |

### 2.2 Hardness Scenarios (Edge + Chaos)

| Category | Count | Examples |
|---|---|---|
| **Timeout boundaries** | 12 | All timeout configs at min/max/exact/±1ms |
| **Protocol corruption** | 8 | Malformed MAP, incomplete TCAP, duplicate messages |
| **Network chaos** | 6 | Delay, loss, jitter, duplicate, reorder, partition |
| **Concurrency** | 5 | Max sessions+1, dialog counter overflow, race conditions |
| **Input mutation** | 10 | Empty, overflow, binary, unicode, missing terminator |
| **Config mutation** | 8 | All configs at extreme values |
| **Resource exhaustion** | 4 | OOM, thread pool exhaustion, file descriptor limit |
| **Recovery** | 6 | Crash recovery, restart mid-dialog, SCTP reconnect |
| **TOTAL** | **59** | |

### 2.3 Regression Scenarios

| ID | Name | Baseline |
|---|---|---|
| REG-01 | TPS baseline check | Must maintain ≥ 95% of previous release TPS |
| REG-02 | Latency baseline check | P99 latency must not increase > 10% |
| REG-03 | Memory leak check | Heap after 30min < 1.1x baseline |
| REG-04 | Dialog leak check | Leaked dialogs after 10k iterations = 0 |
| REG-05 | Error rate check | Error rate < 0.1% |

---

## 3. Protocol-Specific Test Matrix

### 3.1 MAP Dialog State Machine

| State Transition | Test | Priority |
|---|---|---|
| IDLE → WAIT_USER | Basic USSD request | P0 |
| WAIT_USER → WAIT_AS | Forward to Application Server | P0 |
| WAIT_AS → WAIT_USER | AS response back to UE | P0 |
| Any → MERGING | Virtual session merge | P1 |
| MERGING → WAIT_AS | Resume after merge | P1 |
| Any → IDLE (timeout) | Cleanup on timeout | P0 |
| Any → IDLE (ABORT) | Cleanup on TCAP ABORT | P0 |
| Invalid transition | Should be rejected | P1 |

### 3.2 TCAP Transaction

| Scenario | Test |
|---|---|
| BEGIN → CONTINUE → END | Normal flow |
| BEGIN → END | Short dialog |
| BEGIN → CONTINUE → CONTINUE → END | Multi-continue |
| BEGIN → ABORT | User abort |
| BEGIN → (timeout) → ABORT | Timeout abort |
| Duplicate BEGIN | Idempotency |
| CONTINUE without BEGIN | Invalid state |

---

## 4. Performance Test Matrix

| Metric | Target | Warning Threshold | Critical Threshold |
|---|---|---|---|
| TPS | 100k (MAP), 10k (HTTP) | < 95% target | < 80% target |
| P50 latency | < 50ms | > 75ms | > 100ms |
| P99 latency | < 200ms | > 300ms | > 500ms |
| Error rate | < 0.1% | > 0.5% | > 1% |
| Memory (30min) | < 4GB heap | > 80% max heap | > 90% max heap |
| Dialog leaks | 0 | > 0 | > 10 |
| Timer leaks | 0 | > 0 | > 5 |

---

## 5. Integration Test Scenarios

### 5.1 MAP ↔ HTTP Bridge

| Scenario | Description |
|---|---|
| MAP request → HTTP forward → HTTP response → MAP response | Normal bridge |
| MAP request → HTTP timeout → MAP timeout | Bridge timeout |
| Late HTTP response after MAP timeout | Late reconciliation |
| Multiple MAP requests sharing same HTTP session | Session multiplexing |

### 5.2 MAP ↔ gRPC Bridge

| Scenario | Description |
|---|---|
| MAP request → gRPC forward → gRPC response → MAP response | Normal bridge |
| gRPC push → MAP notification | Push scenario |
| gRPC stream disconnect mid-session | Error recovery |

---

## 6. Auto-Scaling Test Scenarios

(For future when QA Team can auto-scale test intensity)

| Phase | TPS | Duration | Purpose |
|---|---|---|---|
| Warmup | 100 → 1k | 30s | Stabilize system |
| Linear ramp | 1k → 10k | 120s | Find initial plateau |
| Steady state | 10k | 300s | Validate sustained load |
| Spike | 10k → 50k | 10s | Spike handling |
| Recovery | 50k → 10k | 60s | Recovery behavior |
| Cool down | 10k → 0 | 30s | Cleanup |
