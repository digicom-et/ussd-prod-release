import { createTool } from "@mastra/core/tools";
import { z } from "zod";
import { execSync } from "child_process";

export const dockerManager = createTool({
  id: "docker-manager",
  description: "Manage USSD Gateway Docker containers (start, stop, logs, status).",
  inputSchema: z.object({
    action: z.enum(["up", "down", "logs", "status", "restart"]),
    composePath: z.string().optional(),
    service: z.string().optional(),
  }),
  outputSchema: z.object({
    success: z.boolean(),
    stdout: z.string(),
    stderr: z.string(),
  }),
  execute: async ({ context }) => {
    const composePath = context.composePath || process.env.USSDGW_GATEWAY_COMPOSE || "/opt/ussdgw-test/gateway";
    const svc = context.service ? ` ${context.service}` : "";
    let cmd = "";
    switch (context.action) {
      case "up": cmd = `docker compose -f ${composePath}/docker-compose.yml up -d${svc}`; break;
      case "down": cmd = `docker compose -f ${composePath}/docker-compose.yml down${svc}`; break;
      case "logs": cmd = `docker compose -f ${composePath}/docker-compose.yml logs --tail=100${svc}`; break;
      case "status": cmd = `docker compose -f ${composePath}/docker-compose.yml ps${svc}`; break;
      case "restart": cmd = `docker compose -f ${composePath}/docker-compose.yml restart${svc}`; break;
    }
    try {
      const stdout = execSync(cmd, { timeout: 120000, encoding: "utf-8" });
      return { success: true, stdout, stderr: "" };
    } catch (err: any) {
      return { success: false, stdout: err.stdout || "", stderr: err.stderr || err.message || "" };
    }
  },
});
