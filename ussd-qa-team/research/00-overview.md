# USSD QA Team — Tổng Quan Dự Án

> **Status:** Research Phase  
> **Date:** 30/06/2026  
> **Goal:** Xây dựng team AI agents tự động hóa toàn bộ quy trình test USSD Gateway 7.3

---

## 1. Bối cảnh

### USSD Gateway 7.3 hiện tại

| Thành phần | Mô tả |
|---|---|
| **Protocol** | MAP/SS7 (2G/3G) + SIP/USSI (4G/5G) |
| **Container** | Mobicents JAIN SLEE (production) / micro-jainslee (R&D) |
| **Performance** | 100k+ concurrent sessions, target 1M TPS |
| **Key features** | Adaptive timeout (EWMA), Virtual Session Bridge, late response reconciliation |
| **Stack** | jSS7 9.5.0, Netty 4.x, WildFly 10, Docker |

### Test infrastructure hiện tại

```
ussdgw-test/          # Production test package (e2e, smoke, deploy/rollback)
product/ussd-loadtest/  # Load test tool (MAP-level + HTTP-level)
product/ussd-test-server/ # Mock MAP server cho test
```

| Test type | Tool | Protocol | Automation |
|---|---|---|---|
| E2E smoke | `ussd-test-server` + scripts | gRPC, MAP, HTTP | Manual scripts |
| MAP load | `UssdSctpClient` (Java) | SCTP/M3UA/SCCP/TCAP/MAP | CLI thủ công |
| HTTP load | `UssdHttpLoadGenerator` (Java) | HTTP/XML | CLI thủ công |
| gRPC smoke | Python scripts | gRPC | Semi-auto |

**Vấn đề:** Tất cả test đều cần con người chạy, phân tích kết quả, và quyết định pass/fail. Không có khả năng tự phát hiện regression, tự sinh test case mới, hay tự thích nghi với thay đổi code.

---

## 2. Mục tiêu USSD QA Team

Xây dựng một **team AI agents** có khả năng:

1. **Auto-test generation** — Tự sinh test case từ code changes, spec, và production traffic patterns
2. **Auto-execution** — Tự chạy test suite, quản lý môi trường (Docker, SCTP, network)
3. **Intelligent analysis** — Phân tích kết quả, phát hiện regression, memory leak, race condition
4. **Self-healing** — Tự sửa test broken do API changes
5. **Hardness engineer** — Chuyên gia tạo edge case, boundary test, chaos engineering
6. **Loop engineer** — Continuous feedback loop: test → analyze → improve → retest

---

## 3. Các thành phần cần có

```
┌──────────────────────────────────────────────────────────────┐
│                     USSD QA TEAM                              │
├───────────────┬───────────────┬───────────────┬───────────────┤
│ Orchestrator  │ Hardness Eng  │ Loop Engineer │ Test Executor │
│ (Brain)       │ (Edge Case    │ (Feedback     │ (Runner)      │
│               │  Generator)   │  Optimizer)   │               │
├───────────────┼───────────────┼───────────────┼───────────────┤
│ Code Analyzer │ Log Analyzer  │ Perf Monitor  │ Env Manager   │
│ (AST diff)    │ (Pattern      │ (Metrics      │ (Docker/      │
│               │  detection)   │  collector)   │  SCTP/Net)    │
└───────────────┴───────────────┴───────────────┴───────────────┘
```

---

## 4. Các framework được nghiên cứu

| Framework | Language | Type | Open Source |
|---|---|---|---|
| **Mastra** | TypeScript | Agent framework | ✅ MIT |
| **Claw.ai** | Rust/TS | Multi-agent orchestration | ✅ |
| **LangChain** | Python/TS | LLM application framework | ✅ MIT |
| **OpenAI SDK** | Python/TS | Direct API agents | ✅ |

→ Chi tiết so sánh: [01-framework-comparison.md](./01-framework-comparison.md)

---

## 5. Nguyên tắc thiết kế

1. **Protocol-aware** — Agents phải hiểu MAP dialog state machine, TCAP transaction, SCTP association
2. **Carrier-grade** — Không được phép gây gián đoạn production; mọi test phải isolated
3. **Immutable test results** — Mọi kết quả test phải auditable, reproducible
4. **Human-in-the-loop** — Hardness engineer đề xuất, con người approve trước khi chạy destructive test
5. **Container-native** — Mọi agent chạy trong Docker, môi trường test ephemeral

---

## 6. Cấu trúc thư mục dự kiến

```
ussd-qa-team/
├── research/           # ← HIỆN TẠI
│   ├── 00-overview.md
│   ├── 01-framework-comparison.md
│   ├── 02-agent-architecture.md
│   ├── 03-hardness-engineer.md
│   ├── 04-loop-engineer.md
│   ├── 05-test-scenarios.md
│   ├── 06-implementation-roadmap.md
│   └── 07-recommendation.md
├── agents/             # Agent implementations
│   ├── orchestrator/
│   ├── hardness-engineer/
│   ├── loop-engineer/
│   └── test-executor/
├── configs/            # Agent configurations
├── test-scenarios/     # Generated test scenarios
├── results/            # Test results & analysis
└── README.md
```

---

## Next Steps

1. Đọc [01-framework-comparison.md](./01-framework-comparison.md) — So sánh các framework
2. Đọc [02-agent-architecture.md](./02-agent-architecture.md) — Kiến trúc chi tiết
3. Đọc [07-recommendation.md](./07-recommendation.md) — Đề xuất cuối cùng
