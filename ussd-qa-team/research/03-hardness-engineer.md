# Hardness Engineer — Edge Case & Chaos Testing

> **Date:** 30/06/2026
> **Role:** Chuyên gia tạo edge case, boundary test, chaos engineering cho USSDGW

---

## 1. Khái niệm "Hardness Engineer"

Hardness Engineer là agent chuyên tìm **điểm yếu** của system bằng cách:
- Tạo test case tại các biên (boundary)
- Đột biến input (mutation)
- Inject lỗi hệ thống (chaos)
- Mô phỏng các tình huống cực đoan (stress corners)

**Khác biệt với test thông thường:** Thay vì test "happy path", Hardness Engineer tập trung vào các scenarios mà developer KHÔNG nghĩ tới.

---

## 2. Edge Case Categories cho USSDGW

### 2.1 Protocol Edge Cases

| Category | Example | Impact |
|---|---|---|
| **MAP dialog** | TCAP ABORT giữa chừng | Dialog leak nếu không cleanup |
| **MAP dialog** | TCAP BEGIN + CONTINUE + END không đúng sequence | State machine corruption |
| **MAP dialog** | Multiple TCAP CONTINUE không có response từ AS | Zombie session |
| **SCTP** | Association breakdown mid-dialog | Session orphan |
| **SCTP** | Multi-homing failover | Race condition |
| **SCCP** | XUDT segmentation > 255 bytes | Reassembly bug |
| **USSD** | USSD string > 182 chars | Buffer overflow |
| **USSD** | Binary USSD (non-text) | Encoding error |

### 2.2 Timeout Edge Cases

| Category | Example | Current Config |
|---|---|---|
| **Adaptive timeout** | EWMA = 1000ms → spike to 7000ms → returns to 1000ms | `asyncgatetimeoutms=7000` |
| **Dialog timeout** | Dialog lives exactly 60000ms → TCAP END at 60001ms | `dialogtimeout=60000` |
| **TCAP timeout** | TCAP lives 89999ms → response at 90001ms | `TCAP=90000` |
| **Bridge TTL** | Session in bridge for 180s → push at 181s | `bridgestatettlsec=180` |
| **Race condition** | AS response + timeout fire simultaneously | Undefined behavior |

### 2.3 Concurrency Edge Cases

| Category | Example |
|---|---|
| **Max sessions** | 100k sessions + 1 → overflow? |
| **Max TPS** | 1M TPS spike → thread pool exhaustion? |
| **Dialog counter** | DialogId counter overflow (int 2^31) |
| **HashMap resize** | ConcurrentHashMap resize during high load |

### 2.4 Network Edge Cases

| Category | Example |
|---|---|
| **Latency** | 1000ms delay (satellite link simulation) |
| **Packet loss** | 10% packet loss → retransmission behavior |
| **Jitter** | Random ±500ms jitter → timeout oscillation |
| **Duplicate** | Duplicate TCAP message → idempotency check |
| **Out-of-order** | Reordered SCCP segments → reassembly logic |

---

## 3. Chaos Injection Toolkit

### 3.1 Network Chaos

```bash
# Inject delay
sudo tc qdisc add dev eth0 root netem delay 500ms 200ms

# Inject packet loss
sudo tc qdisc add dev eth0 root netem loss 10%

# Inject duplicate
sudo tc qdisc add dev eth0 root netem duplicate 5%

# Cleanup
sudo tc qdisc del dev eth0 root
```

### 3.2 Process Chaos

```bash
# Kill SCTP association
ss -K dport 8011

# Pause process (SIGSTOP)
killo -STOP $(pgrep -f ussdgateway)
# Resume after 5s
sleep 5 && kill -CONT $(pgrep -f ussdgateway)

# OOM simulate
docker run --memory=128m ussdgw-test
```

### 3.3 Protocol Chaos

```python
# Malformed MAP message
malformed = bytes([0x00] * 500)  # Zero-filled
send_sctp(malformed, dest=peer_ip, port=8011)

# Incomplete TCAP
send_tcap_begin(dialog_id=12345)
# ... never send CONTINUE or END
# → triggers dialog timeout
```

---

## 4. Mutation Testing Strategy

### 4.1 Input Mutation

| Original | Mutation | Test For |
|---|---|---|
| `"*100#"` | `"*100"` (missing #) | Input validation |
| `"*100#"` | `""` (empty) | Null handling |
| `"*100#"` | `"A" * 1000` (overflow) | Buffer handling |
| `"*100#"` | `"\x00\x00"` (binary) | Encoding safety |
| `"*100#"` | Unicode emoji | Charset handling |

### 4.2 Config Mutation

| Config | Orginal | Mutation |
|---|---|---|
| `asyncgatetimeoutms` | 7000 | 0 (instant timeout) |
| `dialogtimeout` | 60000 | 2147483647 (max int) |
| `maxConcurrent` | 50000 | 1 (single dialog) |
| `workerThreads` | 32 | 0 (no workers) |

---

## 5. Hardness Engineer Agent Design

### Tool Set

```python
# LangChain tool definitions

@tool
def generate_boundary_tests(protocol_layer: str, config: dict) -> list:
    """Sinh boundary test cases cho một protocol layer cụ thể"""
    # Đọc protocol spec → extract boundary values → generate tests
    pass

@tool
def inject_network_chaos(chaos_type: str, params: dict) -> str:
    """Inject network chaos (delay, loss, duplicate)"""
    # Gọi tc, iptables
    pass

@tool
def mutate_ussd_input(base_string: str, mutation_type: str) -> list:
    """Đột biến USSD input string"""
    pass

@tool
def mutate_config(base_config: dict, fuzz_factor: float) -> dict:
    """Đột biến config với fuzz factor"""
    pass
```

### Prompt Template

```
You are a Hardness Engineer specializing in telecom protocol testing.
Your job is to find weaknesses in the USSD Gateway system.

Current system context:
- Protocol: MAP/SS7 + HTTP + gRPC
- Performance target: 100k concurrent, 1M TPS
- Timeouts: asyncgate=7000ms, dialog=60000ms, TCAP=90000ms, bridgeTTL=180s

Changed files: {changed_files}
Impacted layers: {impacted_layers}

Generate edge case test scenarios for these layers.
For each scenario, specify:
1. What you're testing (boundary condition)
2. Expected behavior (from specs)
3. How to execute (specific commands)
4. Risk level (low/medium/high) — high risk requires human approval

Remember: MAP dialog state machine MUST NOT be broken.
```

---

## 6. Safety Constraints

| Constraint | Enforcement |
|---|---|
| Never target production IPs | IP whitelist check |
| Chaos injection requires human sign-off | Approval gate in orchestrator |
| All destructive tests run in sandbox Docker | Separate compose network |
| SCTP association kill must restore within 30s | Auto-recovery script |
| Config mutation must have rollback | Backup config before mutate |
```
