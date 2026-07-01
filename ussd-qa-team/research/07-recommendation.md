# Final Recommendation — USSD QA Team

> **Date:** 30/06/2026
> **Decision:** LangGraph + Sandbox Hybrid Architecture

---

## 1. Recommended Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   LANGGRAPH ORCHESTRATOR                 │
│              (Stateful test pipeline)                    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │              AGENT TEAM (LangChain Tools)         │   │
│  │                                                  │   │
│  │  Orchestrator  ←→  Code Analyzer                 │   │
│  │       ↕              (Git diff → impact map)      │   │
│  │  Loop Engineer  ←→  Log Analyzer                 │   │
│  │       ↕              (Pattern → root cause)       │   │
│  │  Test Executor  ←→  Shell Tools                  │   │
│  │       ↕              (Java/Python/Docker)         │   │
│  │                                                  │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │         HARDNESS SANDBOX (Docker)          │  │   │
│  │  │  Hardness Engineer   Chaos Injector       │  │   │
│  │  │  (Isolated network, no production access) │  │   │
│  │  └────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │          KNOWLEDGE BASE (ChromaDB)               │   │
│  │  Protocol specs │ Known issues │ Test history    │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Why LangGraph

| Reason | Explanation |
|---|---|
| **State machine native** | USSDGW is state-machine heavy (MAP dialog FSM). LangGraph models state machines natively. |
| **Python ecosystem** | Easy data processing (pandas, numpy for metrics). Easy subprocess for Java tools. |
| **LangSmith tracing** | Critical for debugging multi-agent interactions. |
| **RAG integration** | Store 3GPP specs, protocol docs, known issues as retrievable knowledge. |
| **Community + maturity** | Largest AI agent community, stable APIs, many examples. |
| **Tool calling** | Standardized `@tool` decorator, easy to wrap existing scripts. |
| **Conditional edges** | Perfect for Loop Engineer (branch on analyze results). |

---

## 3. Why NOT the Others

| Framework | Reason |
|---|---|
| **Mastra** | Too early stage. TypeScript-only limits Java integration. Smaller community. |
| **Claw.ai** | Very early stage, high discontinuation risk. Rust learning curve for team. Good concepts but not production-ready. |
| **OpenAI SDK** | Vendor lock-in. Too low-level — would need to build everything LangGraph already provides. |

---

## 4. Key Design Decisions

### 4.1 Hardness Engineer: LangChain Agent + Docker Sandbox

- Hardness Engineer runs as a LangChain agent with specialized tools
- All destructive/chaos tests execute in isolated Docker containers
- Network isolation: separate Docker network, no route to production
- Human approval gate for HIGH risk scenarios

### 4.2 Loop Engineer: LangGraph Subgraph

- Loop Engineer is a LangGraph subgraph with its own state machine
- Communicates with main orchestrator via shared state
- Can be invoked iteratively (up to N loops) until fix confirmed or escalated

### 4.3 Tool Wrapping: Shell Commands as LangChain Tools

```python
@tool
def run_map_load_test(params: MapLoadTestParams) -> dict:
    """Run MAP-level load test with given parameters"""
    cmd = f"java -cp lib/* Client {params.to_cli_args()}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=600)
    return {
        "stdout": result.stdout,
        "stderr": result.stderr,
        "returncode": result.returncode
    }
```

→ Tất cả tools wrap shell commands, không cần Java bridge library.

### 4.4 Knowledge Base: ChromaDB + Markdown

- Protocol specs: Markdown files ingested into ChromaDB
- Known issues: JSON patterns with symptom → cause → fix
- Test history: JSON artifacts in `results/` folder

---

## 5. Quick Start Path

```bash
# 1. Create project
mkdir -p ussd-qa-team/agents/{orchestrator,hardness-engineer,loop-engineer,test-executor}
mkdir -p ussd-qa-team/{configs,results,knowledge-base}

# 2. Install dependencies
cd ussd-qa-team
python3 -m venv .venv
source .venv/bin/activate
pip install langchain langgraph langchain-openai chromadb pydantic pyyaml docker

# 3. Create first agent (Orchestrator v0)
# See: agents/orchestrator/

# 4. Wrap first tool (MAP smoke test)
# python agents/test-executor/map_runner.py

# 5. Run first pipeline
# python agents/orchestrator/main.py --trigger manual --test smoke
```

---

## 6. Next Actions

| Priority | Action | Effort |
|---|---|---|
| **P0** | Setup project structure & venv | 1 day |
| **P0** | Wrap existing 5 test scripts as LangChain tools | 2 days |
| **P0** | Build Orchestrator v0 (TRIGGER → EXECUTE → EVALUATE) | 3 days |
| **P1** | Git diff → impact map (Code Analyzer v0) | 2 days |
| **P1** | Docker sandbox for hardness tests | 2 days |
| **P2** | Hardness Engineer: timeout boundary generator | 3 days |
| **P2** | Knowledge Base with 10 known issues | 2 days |
| **P2** | Loop Engineer v0 (1 iteration) | 4 days |

---

## 7. Success Metrics

| Metric | Current | Target (Month 3) |
|---|---|---|
| Test coverage (auto-detected) | 0% | 80% of code changes trigger relevant tests |
| Time from commit to test result | Manual (hours) | < 10 minutes |
| Edge cases generated | 0 | 50+ per release |
| Issues found before production | Manual review | 90% auto-detected |
| Loop iterations to fix | N/A | ≤ 3 iterations |
| Human intervention rate | 100% | < 20% |

---

## 8. TL;DR

> **Use LangGraph + LangChain for the orchestrator, loop engineer, and test executor.**
> **Use Docker sandbox for the hardness engineer's destructive tests.**
> **Wrap existing Java/Python test tools as LangChain `@tool` functions.**
> **Store protocol knowledge in ChromaDB for RAG.**
> **Phase 1: basic pipeline in 4 weeks. Phase 2: intelligence in 8 weeks. Phase 3: full autonomy in 12 weeks.**
