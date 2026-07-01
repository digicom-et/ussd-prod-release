import { createTool } from "@mastra/core/tools";
import { z } from "zod";
import { execSync } from "child_process";

/** HTTP-level load test runner */
export const httpRunner = createTool({
  id: "http-runner",
  description: "Run HTTP-level load test against USSD Gateway HTTP interface.",
  inputSchema: z.object({
    baseUrl: z.string().default("http://localhost:8080/ussdhttpdemo/"),
    targetTps: z.number().default(1000),
    workerThreads: z.number().default(16),
    maxConcurrent: z.number().default(10000),
    durationSec: z.number().default(60),
    ussdString: z.string().default("*100#"),
  }),
  outputSchema: z.object({
    success: z.boolean(),
    stdout: z.string(),
    stderr: z.string(),
    exitCode: z.number(),
  }),
  execute: async ({ context }) => {
    const { baseUrl, targetTps, workerThreads, maxConcurrent, durationSec, ussdString } = context;
    const jar = process.env.USSDGW_HTTP_JAR || "/opt/ussdgw-test/http-level/lib/loadtest.jar";
    const cmd = `java -Xms2g -Xmx2g -cp "${jar}" org.mobicents.ussd.loadtest.UssdHttpLoadGenerator ${baseUrl} ${targetTps} ${workerThreads} ${maxConcurrent} ${durationSec} "${ussdString}"`;
    try {
      const stdout = execSync(cmd, { timeout: (durationSec + 30) * 1000, encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 });
      return { success: true, stdout, stderr: "", exitCode: 0 };
    } catch (err: any) {
      return { success: false, stdout: err.stdout || "", stderr: err.stderr || err.message || "", exitCode: err.status || 1 };
    }
  },
});
