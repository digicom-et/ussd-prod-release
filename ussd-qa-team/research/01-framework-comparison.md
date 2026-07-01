# Framework Comparison — USSD QA Agent Team

> **Date:** 30/06/2026
> **Goal:** Đánh giá framework phù hợp nhất để xây dựng team AI agents tự động test USSDGW

---

## 1. Tổng quan các framework

### 1.1 Mastra

| Tiêu chí | Đánh giá |
|---|---|
| **Website** | https://mastra.ai |
| **Language** | TypeScript |
| **License** | MIT |
| **Maturity** | Early/mid stage (2024+) |
| **Core concept** | Agent framework với built-in tools, workflows, memory, evals |

**Điểm mạnh:**
- 🟢 **Workflow engine** tích hợp sẵn — dễ tạo multi-step test pipeline
- 🟢 **Built-in evals** — có sẵn hệ thống đánh giá (evals) cho agent outputs
- 🟢 **Tool system** — dễ dàng wrap existing test tools (Java CLI, Python scripts) thành agent tools
- 🟢 **TypeScript** — dễ tích hợp với CI/CD pipeline (Node.js ecosystem)
- 🟢 **Memory/RAG** — có storage layer cho context retention
- 🟢 **Open source MIT** — không lock-in

**Điểm yếu:**
- 🔴 **Early stage** — API đang thay đổi, ít production case study
- 🔴 **TypeScript only** — không native Java, cần wrapper cho jSS7 tools
- 🟡 **Community** — nhỏ hơn LangChain

**Phù hợp cho:** Orchestrator, Test Executor (tool wrapping), Loop Engineer (eval + feedback)

---

### 1.2 Claw.ai

| Tiêu chí | Đánh giá |
|---|---|
| **Website** | https://claw.ai |
| **Language** | Rust (core) + TypeScript (SDK) |
| **License** | Open source |
| **Maturity** | Very early (2025+) |
| **Core concept** | Multi-agent orchestration với shared blackboard, role-based agents |

**Điểm mạnh:**
- 🟢 **Multi-agent native** — sinh ra để làm multi-agent, không phải add-on
- 🟢 **Shared blackboard** — agents giao tiếp qua shared memory, phù hợp cho loop engineer
- 🟢 **Role-based** — dễ map sang Hardness Engineer, Loop Engineer, Test Executor
- 🟢 **Rust performance** — phù hợp cho high-throughput test execution
- 🟢 **Sandboxed execution** — agents chạy isolated, an toàn cho destructive test

**Điểm yếu:**
- 🔴 **Very early stage** — documentation hạn chế, API chưa ổn định
- 🔴 **Rust learning curve** — team cần biết Rust để extend
- 🔴 **Ecosystem** — ít integrations hơn LangChain
- 🔴 **Risk** — dự án có thể discontinued

**Phù hợp cho:** Multi-agent orchestration nếu risk chấp nhận được, Hardness Engineer (sandbox), internal communication

---

### 1.3 LangChain / LangGraph

| Tiêu chí | Đánh giá |
|---|---|
| **Website** | https://langchain.com |
| **Language** | Python, TypeScript |
| **License** | MIT |
| **Maturity** | Mature (2023+) |
| **Core concept** | LLM application framework với chains, agents, tools, graphs |

**Điểm mạnh:**
- 🟢 **Mature ecosystem** — nhiều integrations, community lớn, documentations tốt
- 🟢 **LangGraph** — stateful graph-based agent orchestration, phù hợp test pipeline
- 🟢 **Python** — dễ viết test logic, data analysis, integration với JVM qua subprocess
- 🟢 **Tool calling** — standard hóa tool interface, dễ wrap existing test tools
- 🟢 **LangSmith** — debugging, tracing, evaluation platform (loop engineer)
- 🟢 **Multi-agent patterns** — có sẵn supervisor, hierarchical, swarm
- 🟢 **RAG built-in** — dễ tích hợp knowledge base về USSD protocol

**Điểm yếu:**
- 🟡 **Heavy abstraction** — nhiều layer, dễ over-engineer
- 🟡 **Breaking changes** — history có nhiều breaking changes giữa versions
- 🟡 **Python** — cần bridge sang Java tools (subprocess, REST, gRPC)
- 🟡 **Cost** — nhiều LLM calls có thể tốn kém nếu không optimize

**Phù hợp cho:** Orchestrator + Loop Engineer (LangGraph), Code Analyzer, Log Analyzer, Knowledge base


### 1.4 OpenAI Agents SDK

| Tiêu chí | Đánh giá |
|---|---|
| **Website** | https://platform.openai.com/docs/guides/agents |
| **Language** | Python, TypeScript |
| **License** | MIT |
| **Maturity** | New (2025, successor to Swarm) |
| **Core concept** | Lightweight agent SDK: handoffs, guardrails, tracing |

**Điểm mạnh:**
- 🟢 **Simple API** — ít abstraction, dễ hiểu, dễ debug
- 🟢 **Handoffs** — agent chuyển giao task cho agent khác
- 🟢 **Guardrails** — input/output validation, quan trọng cho test safety
- 🟢 **Tracing built-in** — dễ track execution flow
- 🟢 **OpenAI native** — tận dụng tối đa GPT-4o cho code analysis
- 🟢 **Lightweight** — ít dependency, phù hợp microservice

**Điểm yếu:**
- 🔴 **OpenAI lock-in** — chỉ hoạt động với OpenAI models
- 🔴 **New/immature** — ít production case study
- 🔴 **Ít built-in tools** — phải tự build nhiều infrastructure

**Phù hợp cho:** Prototype nhanh, Code Analyzer (OpenAI codex)

---

## 2. So sánh trực tiếp

| Tiêu chí | Mastra | Claw.ai | LangChain | OpenAI SDK |
|---|---|---|---|---|
| **Multi-agent** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| **Workflow/pipeline** | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **Ecosystem/integrations** | ⭐⭐ | ⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ |
| **Performance** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| **Maturity/stability** | ⭐⭐ | ⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Learning curve** | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Protocol-awareness** | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| **Self-healing test** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Hardness engineer fit** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| **Loop engineer fit** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |

---

## 3. Phân tích theo use case USSDGW

### 3.1 Orchestrator (Brain)
Cần: workflow engine, state management, retry logic, parallel execution
- **Best fit:** LangGraph (stateful graph) hoặc Mastra (workflow engine)
- LangGraph: model test pipeline như state machine (phù hợp MAP dialog FSM)
- Mastra: Workflow DSL dễ đọc, built-in retry

### 3.2 Hardness Engineer
Cần: tạo edge cases, boundary tests, chaos injection, mutation testing
- **Best fit:** LangChain + custom tools hoặc Claw.ai (sandbox)
- LangChain: build RAG từ protocol specs, sinh test case từ spec
- Claw.ai: Sandboxed execution an toàn cho destructive tests

### 3.3 Loop Engineer
Cần: analyze results → suggest improvements → re-test → measure delta
- **Best fit:** LangGraph (feedback loop) hoặc Claw.ai (blackboard)
- LangGraph: model continuous loop với conditional edges
- Claw.ai: Blackboard pattern cho shared learning giữa agents

### 3.4 Test Executor
Cần: gọi Java/Python test tools, capture output, parse results
- **Best fit:** LangChain tools hoặc Mastra tools
- Cả hai đều dễ wrap shell commands thành agent tools

---

## 4. Compatibility với stack hiện tại

| Integration point | Cách thực hiện |
|---|---|
| **MAP load test** | Subprocess `java -cp lib/* ...Client` |
| **HTTP load test** | Subprocess `java ...UssdHttpLoadGenerator` |
| **gRPC smoke** | Subprocess `ussd_as_server.py` |
| **Docker management** | `docker compose` qua shell commands |
| **Jolokia metrics** | HTTP GET `http://localhost:8080/jolokia/` |
| **SCTP check** | `lsmod | grep sctp` qua shell |
| **Log analysis** | File tail hoặc Docker logs API |
| **Protocol specs** | RAG từ 3GPP TS 24.390, TS 29.002, MAP specs |

→ Tất cả đều có thể wrap qua shell command tools → LangChain/Python ecosystem mạnh nhất về data processing.

---

## 5. Risk Assessment

| Framework | Continuity Risk | Lock-in Risk | Performance Risk |
|---|---|---|---|
| Mastra | Medium (early) | Low (MIT, TS) | Low |
| Claw.ai | High (very early) | Low (open source) | Medium (Rust) |
| LangChain | Low (mature) | Medium (ecosystem) | Low |
| OpenAI SDK | Medium (OpenAI) | High (vendor) | Low |

---

## Kết luận sơ bộ

→ **LangChain/LangGraph là lựa chọn an toàn và mạnh nhất** cho USSD QA Team

→ **Claw.ai là wildcard thú vị** cho hardness engineer (sandbox), nhưng risk cao

→ **Khuyến nghị hybrid:** LangGraph làm orchestrator chính, custom sandbox cho hardness test

→ Xem [07-recommendation.md](./07-recommendation.md)
