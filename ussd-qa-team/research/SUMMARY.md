# USSD QA Team — Tổng Kết Nghiên Cứu

> **Date:** 30/06/2026
> **Status:** ✅ Research Complete — Ready for Phase 1

---

## 1. Mục tiêu

Xây dựng team AI agents tự động hóa toàn bộ quy trình test USSD Gateway 7.3:
- Auto-test generation từ code changes
- Hardness Engineer (edge case, chaos, boundary)
- Loop Engineer (analyze → fix → verify → learn)
- Tự động phát hiện regression, memory leak, race condition

---

## 2. Hiện trạng test

| Test type | Tool | Tự động? |
|---|---|---|
| E2E smoke | Script shell + Python | ❌ Manual |
| MAP load (100k TPS) | Java CLI | ❌ Manual |
| HTTP load | Java CLI | ❌ Manual |
| gRPC smoke | Python scripts | ❌ Semi |

→ Tất cả cần con người chạy + phân tích. Không có auto-regression detection.

---

## 3. Kiến trúc đề xuất

```
┌────────────────────────────────────────────┐
│        ORCHESTRATOR (Mastra/LangGraph)      │
│                                             │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │ HARDNESS │  │  LOOP    │  │   TEST    │ │
│  │ ENGINEER │  │ ENGINEER │  │ EXECUTOR  │ │
│  │ (Docker  │  │ (analyze │  │ (Java     │ │
│  │ sandbox) │  │ →fix→ver)│  │ subprocess│ │
│  └──────────┘  └──────────┘  └───────────┘ │
│                                             │
│  ┌──────────┐  ┌──────────┐                │
│  │  CODE    │  │   LOG    │                │
│  │ ANALYZER │  │ ANALYZER │                │
│  └──────────┘  └──────────┘                │
│                                             │
│  ┌──────────────────────────┐              │
│  │  KNOWLEDGE BASE (ChromaDB)│              │
│  └──────────────────────────┘              │
└────────────────────────────────────────────┘
```

---

## 4. So sánh Framework

| Tiêu chí | LangGraph | Mastra | CrewAI | OpenAI SDK |
|---|---|---|---|---|
| Multi-agent | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| Loop/feedback | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐ |
| Branching | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ | ⭐ |
| Ecosystem | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐ |
| Java tool wrap | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ |
| Visual debug | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Maturity | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |

---

## 5. Quyết định

| Framework | Vai trò | Lý do |
|---|---|---|
| **Mastra** | Phase 1 orchestrator | `.dountil()` loop sẵn, `.parallel()` test, Studio debug |
| **LangGraph** | Phase 2+ nâng cấp | Conditional edges động cho Loop Engineer phức tạp |
| **Docker sandbox** | Hardness Engineer | Isolated network, an toàn destructive tests |
| **ChromaDB** | Knowledge Base | RAG protocol specs + known issues |
| **Shell subprocess** | Tool wrapping | Gọi Java CLI test tools |

---

## 6. Hardness Engineer — 59 scenarios

| Category | Count |
|---|---|
| Timeout boundaries | 12 |
| Protocol corruption | 8 |
| Network chaos | 6 |
| Concurrency | 5 |
| Input mutation | 10 |
| Config mutation | 8 |
| Resource exhaustion | 4 |
| Recovery | 6 |

---

## 7. Loop Engineer — Workflow

```
Test Results → Analyze → Hypothesize → Verify → Learn
                                         ↑        │
                                         └────────┘ (loop nếu still failing)
```

Terminate khi: pass, max 5 iterations, diminishing returns, hoặc escalate human.

---

## 8. Lộ trình

| Phase | Tuần | Mục tiêu |
|---|---|---|
| **1. Foundation** | 1-4 | Pipeline cơ bản: trigger → execute → evaluate |
| **2. Intelligence** | 5-8 | Hardness + Loop Engineer hoạt động |
| **3. Autonomy** | 9-12 | Auto-fix PR, JIRA integration, dashboard |

---

## 9. File liên quan

| File | Nội dung |
|---|---|
| [00-overview.md](./00-overview.md) | Tổng quan dự án |
| [01-framework-comparison.md](./01-framework-comparison.md) | So sánh chi tiết 4 framework |
| [02-agent-architecture.md](./02-agent-architecture.md) | Kiến trúc 6 agents |
| [03-hardness-engineer.md](./03-hardness-engineer.md) | Edge case, chaos, mutation |
| [04-loop-engineer.md](./04-loop-engineer.md) | Feedback loop engine |
| [05-test-scenarios.md](./05-test-scenarios.md) | MAP FSM, TCAP, perf matrix |
| [06-implementation-roadmap.md](./06-implementation-roadmap.md) | 3 phases / 12 weeks |
| [07-recommendation.md](./07-recommendation.md) | Đề xuất cuối cùng |

---

## 10. Next Action

```bash
# Phase 1 — Week 1
mkdir -p ussd-qa-team/agents/{orchestrator,test-executor}
mkdir -p ussd-qa-team/{configs,results,knowledge-base}
npm create mastra@latest    # hoặc pip install langgraph
```
