# Implementation Roadmap — USSD QA Team

> **Date:** 30/06/2026
> **Timeline:** 3 phases, 12 weeks

---

## Phase 1: Foundation (Week 1-4)

### Mục tiêu: Chạy được basic test pipeline với AI agent

| Week | Deliverable | Details |
|---|---|---|
| **W1** | Environment setup | Docker compose for QA team, Python venv, LangChain setup |
| **W1** | Tool wrapping | Wrap existing test scripts as LangChain tools: `map_runner`, `http_runner`, `docker_mgr` |
| **W2** | Orchestrator v0 | LangGraph StateGraph với 3 states: TRIGGER → EXECUTE → EVALUATE |
| **W2** | Code Analyzer v0 | Git diff parser → impact map (basic file→layer mapping) |
| **W3** | Test Executor v0 | Auto-run smoke tests (E2E-01 to E2E-05) từ Code Analyzer recommendation |
| **W3** | Log Analyzer v0 | Parse Docker logs, detect ERROR lines, count warnings |
| **W4** | Integration test | End-to-end: git push → auto detect changes → run relevant tests → report |

### Tech decisions (Phase 1)

```python
# requirements.txt
langchain>=0.3.0
langgraph>=0.2.0
langchain-openai>=0.2.0
pydantic>=2.0
pyyaml>=6.0
docker>=7.0
```

### Success criteria
- [ ] Git push trigger → auto run smoke tests → pass/fail report < 5 min
- [ ] Manual trigger → run all L1-L3 load tests → metrics collected

---

## Phase 2: Intelligence (Week 5-8)

### Mục tiêu: Hardness Engineer + Loop Engineer hoạt động

| Week | Deliverable | Details |
|---|---|---|
| **W5** | Hardness Engineer v0 | Edge case generator cho timeout boundaries |
| **W5** | Chaos injection (safe) | Network delay injection trong Docker network |
| **W6** | Mutation testing v0 | USSD input mutation, config fuzzing |
| **W6** | Knowledge Base setup | Vector DB (ChromaDB) lưu known issues pattern |
| **W7** | Loop Engineer v0 | Analyze → Hypothesize → Verify → Learn (1 iteration) |
| **W7** | A/B test harness | Parallel Docker containers cho A/B testing |
| **W8** | Hardness Engineer + Loop integration | Hardness generates → Loop analyzes failures → proposes fixes |

### Success criteria
- [ ] Hardness Engineer generates ≥ 20 unique edge cases from code diff
- [ ] Loop Engineer successfully identifies và verifies ít nhất 1 real issue
- [ ] KB chứa ít nhất 10 known issue patterns

---

## Phase 3: Autonomy (Week 9-12)

### Mục tiêu: Full autonomous QA pipeline

| Week | Deliverable | Details |
|---|---|---|
| **W9** | Auto-scaling test intensity | Dựa trên system metrics, tự điều chỉnh TPS |
| **W9** | Regression baseline | Lưu historical baseline cho mỗi release |
| **W10** | Auto-fix PR | Loop Engineer verified fix → auto-create GitHub PR |
| **W10** | JIRA integration | Escalation → JIRA ticket với full context |
| **W11** | Dashboard | Web UI showing: test history, KB growth, health metrics |
| **W11** | Multi-branch support | Test đồng thời multiple feature branches |
| **W12** | Production shadow mode | Replay production traffic in sandbox (read-only) |
| **W12** | Documentation + handoff | Full docs, runbooks, demo |

### Success criteria
- [ ] 80% of common issues auto-detected & auto-fixed
- [ ] Mean time to detect regression < 10 minutes
- [ ] Zero production-impacting bugs after QA Team sign-off

---

## Technology Stack (Final)

| Component | Technology | Version |
|---|---|---|
| **Agent Framework** | LangChain + LangGraph | 0.3+ |
| **LLM** | OpenAI GPT-4o / Claude Sonnet 4 | Latest |
| **Vector DB** | ChromaDB | 0.5+ |
| **Orchestration** | LangGraph StateGraph | 0.2+ |
| **Container** | Docker + Docker Compose | 24+ |
| **Monitoring** | Jolokia JMX → Prometheus | Latest |
| **CI/CD Integration** | GitHub Actions / Webhook | - |
| **Database** | SQLite (local) + JSON artifacts | - |
| **Language** | Python 3.12+ | 3.12+ |

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| LangChain breaking changes | Medium | High | Pin versions, integration tests cho tool calling |
| LLM hallucination in analysis | Medium | Medium | Always verify with actual log data; human review for critical |
| SCTP kernel module issues | Low | High | Pre-flight check, graceful degradation |
| Docker resource contention | Medium | Medium | Resource limits per container, scheduling |
| False positives (over-alerting) | High | Low | Confidence threshold, human-in-the-loop for new patterns |

---

## Team & Ownership

| Role | Owner | Responsibility |
|---|---|---|
| QA Architect | TBD | Overall design, code reviews |
| Agent Developer | TBD | LangChain tools, prompts, workflows |
| DevOps | TBD | Docker, CI/CD, environment |
| Domain Expert | Huu Nhan Tran | USSDGW protocol knowledge, test scenarios |

---

## Cost Estimation

| Item | Monthly Estimate |
|---|---|
| OpenAI API (GPT-4o, ~1000 calls/day) | $300-500 |
| Cloud VM (32GB RAM, 8 vCPU) | $200-400 |
| LangSmith (optional) | $0-50 |
| **Total** | **$500-950/month** |

> 💡 Có thể giảm cost bằng self-hosted model (Llama 3 70B) nếu cần privacy + cost control.
