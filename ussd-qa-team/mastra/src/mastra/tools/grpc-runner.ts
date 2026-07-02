import { createTool } from "@mastra/core/tools";
import { z } from "zod";
import { execSync } from "child_process";
import { PKG_ROOT } from "../config";

export const grpcRunner = createTool({
  id: "grpc-runner",
  description: "Run gRPC smoke test against USSD Gateway.",
  inputSchema: z.object({
    scriptPath: z.string().optional(),
    port: z.number().default(8443),
  }),
  outputSchema: z.object({
    success: z.boolean(),
    stdout: z.string(),
    stderr: z.string(),
    exitCode: z.number(),
  }),
  execute: async ({ context }) => {
    const script = context.scriptPath || process.env.USSDGW_GRPC_SCRIPT || `${PKG_ROOT}/scripts/05-start-grpc-as.sh`;
    try {
      const stdout = execSync(`bash ${script}`, { timeout: 30000, encoding: "utf-8" });
      return { success: true, stdout, stderr: "", exitCode: 0 };
    } catch (err: any) {
      return { success: false, stdout: err.stdout || "", stderr: err.stderr || err.message || "", exitCode: err.status || 1 };
    }
  },
});
