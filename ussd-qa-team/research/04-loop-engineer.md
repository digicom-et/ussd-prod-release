# Loop Engineer — Continuous Feedback & Improvement

> **Date:** 30/06/2026
> **Role:** Động cơ học liên tục (continuous learning loop) của QA team

---

## 1. Khái niệm "Loop Engineer"

Loop Engineer là agent thực hiện vòng lặp phản hồi liên tục:

```
         ┌──────────────────────────────────┐
         │                                  │
         ▼                                  │
┌─────────────┐   ┌─────────────┐   ┌──────────────┐
│  ANALYZE    │→  │  HYPOTHESIZE│→  │   VERIFY     │
│  failures   │   │  root cause │   │  re-test     │
└─────────────┘   └─────────────┘   └──────┬───────┘
         │                                  │
         │         ┌─────────────┐          │
         │         │   LEARN     │◄─────────┘
         │         │  update KB  │
         │         └──────┬──────┘
         │                │
         └────────────────┘
           (if still failing)
```

**Khác biệt với CI/CD thông thường:** Loop Engineer không chỉ báo fail/pass mà còn tự động phân tích nguyên nhân, đề xuất fix, và verify fix đó có hiệu quả không.

---

## 2. The Analyze Phase

### 2.1 Failure Classification

```python
class FailureType(Enum):
    TIMEOUT = "timeout"                # Test chạy quá lâu
    CRASH = "crash"                    # Process chết
    WRONG_OUTPUT = "wrong_output"      # Output không đúng expected
    RESOURCE_LEAK = "resource_leak"    # Memory/dialog/timer leak
    REGRESSION = "regression"          # Đã pass trước đây, giờ fail
    FLAKY = "flaky"                    # Lúc pass lúc fail
    PERFORMANCE_DEGRADATION = "perf"   # TPS/latency tồi hơn baseline
```

### 2.2 Root Cause Analysis Pipeline

```
Failure detected
    ↓
Classify failure type
    ↓
Extract relevant logs (time window around failure)
    ↓
Pattern match against known issues (KB)
    ↓
If known: suggest known fix
If unknown: correlate logs → metrics → code changes → generate hypothesis
```

### 2.3 Known Issue Patterns (KB)

| Pattern | Symptom | Root Cause | Fix |
|---|---|---|---|
| DialogCount mismatch | `leaked dialogs: N` | Missing TCAP END/ABORT handling | `dialogtimeout` cleanup |
| Memory heap growth | `heap > 90% after 30min` | Dialog object not released | `dialog.destroy()` in finally |
| TPS plateau at 5k | `TPS 5000 (target 10000)` | Thread pool size too small | Increase `workerThreads` |
| Late response dropped | `lateResponseDroppedCount > 0` | `bridgestatettlsec` too short | Increase TTL or add reconciliation |
| SCTP reconnection storm | `SCTP: connect/disconnect loop` | Association timeout mismatch | Align SCTP timeouts |

---

## 3. The Hypothesize Phase

### 3.1 Hypothesis Generation

Loop Engineer tạo hypothesis dạng:

```json
{
  "hypothesis_id": "H-2026-0630-001",
  "failure": "Late response dropped at TPS 50000",
  "root_cause_suspected": "bridgestatettlsec=180 quá ngắn khi AS lag",
  "proposed_fix": "Tăng bridgestatettlsec từ 180 lên 300",
  "expected_improvement": "lateResponseDroppedCount → 0",
  "regression_risk": ["Memory tăng do giữ session lâu hơn", "Zombie session risk"],
  "confidence": 0.75
}
```

### 3.2 Hypothesis Ranking

Sort hypotheses by:
1. **Confidence score** (dựa trên similarity với known issues)
2. **Fix effort** (config change < code change)
3. **Regression risk** (low risk ưu tiên)
4. **Impact magnitude** (số lượng tests affected)

---

## 4. The Verify Phase

### 4.1 A/B Testing for Fixes

```
┌─────────────────────────┐  ┌─────────────────────────┐
│   CONTAINER A            │  │   CONTAINER B            │
│   Current config         │  │   Patched config         │
│   bridgestatettlsec=180  │  │   bridgestatettlsec=300  │
└───────────┬─────────────┘  └───────────┬─────────────┘
            │                             │
            └─────────┬───────────────────┘
                      │
              ┌───────▼────────┐
              │  SAME LOAD TEST │
              │  TPS=50000, 60s │
              └───────┬────────┘
                      │
         ┌────────────┴────────────┐
         ▼                         ▼
┌─────────────────┐      ┌─────────────────┐
│ lateDrop: 142    │      │ lateDrop: 0      │
│ TPS: 49800       │      │ TPS: 49600       │
│ heap: 72%        │      │ heap: 74%        │
└─────────────────┘      └─────────────────┘

→ DELTA: lateDrop -100%, heap +2% (acceptable)
→ VERDICT: FIX CONFIRMED ✓
```

### 4.2 Delta Measurement

```python
class DeltaReport:
    metric: str           # e.g., "lateResponseDroppedCount"
    baseline_value: float # 142
    patched_value: float  # 0
    delta_pct: float      # -100%
    direction: str        # "improvement" / "degradation" / "no_change"
    side_effects: list    # ["heap +2.7%", "TPS -0.4%"]
    confidence: float     # 0.95
```

---

## 5. The Learn Phase

### 5.1 Knowledge Base Update

```python
# Sau mỗi loop iteration successful
def update_knowledge_base(session_id: str, hypothesis: dict, delta: DeltaReport):
    if delta.direction == "improvement" and delta.confidence > 0.8:
        # Lưu vào KB
        kb.add(
            pattern=f"{hypothesis.failure}",
            root_cause=hypothesis.root_cause_suspected,
            fix=hypothesis.proposed_fix,
            evidence=delta,
            source=session_id
        )
```

### 5.2 Continuous Learning Metrics

| Metric | Description | Target |
|---|---|---|
| **Fix rate** | Hypotheses confirmed / total | > 60% |
| **Mean time to fix** | Time from failure to verified fix | < 30 min |
| **Regression rate** | Fixes causing new failures | < 5% |
| **KB growth** | New patterns added per week | > 10 |
| **Auto-fix rate** | Fixes applied without human | > 50% |

---

## 6. Loop Termination Conditions

Loop dừng khi:

1. **SUCCESS:** All tests pass with delta ≥ threshold
2. **MAX_ITERATIONS:** Đã loop N lần (default: 5)
3. **DIMINISHING_RETURNS:** 3 loops liên tiếp delta < 1%
4. **HUMAN_NEEDED:** Hypothesis confidence < 0.5 → escalate to human
5. **STUCK:** Same hypothesis repeated 2x → escalate

---

## 7. Loop Engineer Agent Design

### LangGraph State

```python
class LoopState(TypedDict):
    iteration: int
    failures: List[Failure]
    hypotheses: List[Hypothesis]
    verified_fixes: List[DeltaReport]
    kb_updates: List[str]
    need_human: bool
    termination_reason: Optional[str]
```

### Conditional Edges

```python
def should_continue(state: LoopState) -> str:
    if all_tests_pass(state):
        return "complete"
    if state["iteration"] >= state["max_iterations"]:
        return "escalate_to_human"
    if state["need_human"]:
        return "escalate_to_human"
    return "continue_loop"
```

### Tool Set

```python
@tool
def analyze_failures(test_results: list) -> list:
    """Phân tích test failures → classification + root cause hypothesis"""
    pass

@tool
def propose_fix(failure: dict, kb: dict) -> dict:
    """Đề xuất fix từ KB hoặc generate mới"""
    pass

@tool
def verify_fix(hypothesis: dict, baseline: dict) -> DeltaReport:
    """A/B test fix vs baseline → delta report"""
    pass

@tool
def update_kb(verified: DeltaReport, hypothesis: dict) -> str:
    """Cập nhật knowledge base với pattern mới"""
    pass
```

---

## 8. Integrations

### 8.1 Git Integration

```python
# Khi fix confirmed: auto-create PR
@tool
def create_fix_pr(hypothesis: dict, delta: DeltaReport):
    branch = f"qa-fix/{hypothesis.hypothesis_id}"
    os.system(f"git checkout -b {branch}")
    # Apply config/code change
    os.system(f"git commit -m 'QA Auto-fix: {hypothesis.proposed_fix}")
    os.system(f"git push origin {branch}")
    # Create PR via API
```

### 8.2 JIRA Integration

```python
# Khi escalate to human: create JIRA ticket
@tool
def escalate_to_jira(failure: dict, loop_state: LoopState):
    jira.create_issue(
        summary=f"QA Loop stuck: {failure.type}",
        description=f"After {loop_state.iteration} iterations...",
        priority="High"
    )
```
