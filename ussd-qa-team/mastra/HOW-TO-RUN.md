# Cách Chạy USSD QA Team Multi-Agent

> **Date:** 01/07/2026
> **Phase 1 Foundation**

---

## 1. Khởi động

```bash
cd ussdgw-prod-release/ussd-qa-team/mastra
export NVM_DIR="$HOME/.config/nvm" && . "$NVM_DIR/nvm.sh"
export OPENAI_API_KEY="sk-your-key"
npx mastra dev
```

Mastra dev mở **Studio** (web UI) tại `http://localhost:4111` — test agent, chạy workflow, xem graph.

---

## 2. Gọi Workflow từ code

```typescript
const pipeline = mastra.getWorkflow("test-pipeline");
const run = await pipeline.createRun();
const result = await run.start({
  inputData: { trigger: "manual", message: "Test MAP after config change" }
});
// result.verdict → "PASS" | "FAIL" | "WARNING"
// result.report  → full text report
```

---

## 3. Flow từng bước

```
Bạn gọi: { trigger: "manual", message: "..." }
         │
    ┌────▼─────┐
    │ TRIGGER  │  Nhận signal, nếu webhook → git diff HEAD~1
    │  step    │
    └────┬─────┘
         │ { trigger, message, gitDiff? }
    ┌────▼─────┐
    │ ANALYZE  │  Parse git diff → tìm keyword (MAP/SCTP/HTTP/gRPC...)
    │  step    │  → impactedLayers + riskLevel + recommendedTests
    └────┬─────┘
         │ { ..., impactedLayers, riskLevel, recommendedTests }
    ┌────▼─────┐
    │ EXECUTE  │  Loop qua recommendedTests → chạy tools tương ứng
    │  step    │  map-load → mapRunner tool (execSync java...)
    │          │  http-load → httpRunner tool
    │          │  grpc-smoke → grpcRunner tool
    └────┬─────┘
         │ { ..., testResults: [{status, details}] }
    ┌────▼─────┐
    │ EVALUATE │  Đếm PASS/FAIL/SKIPPED → verdict
    │  step    │  Tạo structured report
    └────┬─────┘
         │
    KẾT QUẢ: { verdict: "PASS", report: "...", summary: "3P/0F/0S" }
```

---

## 4. Agent vs Workflow

| | Agent | Workflow |
|---|---|---|
| **Dùng LLM?** | ✅ Có (GPT-4o) | ❌ Không (code logic) |
| **Quyết định?** | Tự suy luận | Theo step cố định |
| **Dùng tools?** | ✅ Gọi tools qua LLM | ❌ Step gọi trực tiếp |
| **Ví dụ** | `test-executor` agent nhận lệnh "chạy MAP test" → tự gọi `mapRunner` tool | `test-pipeline` workflow chạy cố định 4 step |

**Phase 1:** Workflow là chính (deterministic)
**Phase 2:** Agent lớn hơn — Hardness Engineer (LLM sinh edge case), Loop Engineer (LLM phân tích failure)

---

## 5. Cấu trúc project

```
mastra/
├── .env                    # OPENAI_API_KEY + USSDGW paths
├── package.json            # mastra v1.17, @mastra/core v1.48
├── tsconfig.json
└── src/mastra/
    ├── index.ts            # Mastra instance (3 agents + 1 workflow)
    ├── agents/
    │   ├── orchestrator.ts # Điều phối pipeline
    │   ├── code-analyzer.ts# Git diff → impacted layers
    │   └── test-executor.ts# Gọi 4 tools
    ├── workflows/
    │   └── test-pipeline.ts# TRIGGER → ANALYZE → EXECUTE → EVALUATE
    └── tools/
        ├── map-runner.ts   # java -cp lib/* Client ...
        ├── http-runner.ts  # java ...UssdHttpLoadGenerator
        ├── grpc-runner.ts  # bash 05-start-grpc-as.sh
        └── docker-manager.ts# docker compose up/down/logs
```

---

## 6. Phase 2 — Sẽ thêm

```
test-pipeline
  .then(triggerStep)
  .then(analyzeStep)
  .branch([...])           ← Route theo protocol layer
  .parallel([...])         ← Chạy MAP + HTTP + gRPC song song
  .dountil(loopWorkflow)   ← Loop Engineer feedback loop
  .then(evaluateStep)
  .commit()
```
