import { Mastra } from "@mastra/core";
import { orchestrator } from "./agents/orchestrator";
import { codeAnalyzer } from "./agents/code-analyzer";
import { testExecutor } from "./agents/test-executor";
import { testPipeline } from "./workflows/test-pipeline";
import { scenarioRunner } from "./workflows/scenario-runner";

export const mastra = new Mastra({
  agents: {
    orchestrator,
    "code-analyzer": codeAnalyzer,
    "test-executor": testExecutor,
  },
  workflows: {
    "test-pipeline": testPipeline,
    "scenario-runner": scenarioRunner,
  },
});
