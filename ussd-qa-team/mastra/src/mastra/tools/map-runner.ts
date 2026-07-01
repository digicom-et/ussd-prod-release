import { createTool } from "@mastra/core/tools";
import { z } from "zod";
import { execSync } from "child_process";

/**
 * MAP-level load test runner
 * Wraps: java -cp lib/* org.mobicents.protocols.ss7.map.load.ussd.Client
 */
export const mapRunner = createTool({
  id: "map-runner",
  description:
    "Run MAP-level (SS7) load test against USSD Gateway. Tests SCTP → M3UA → SCCP → TCAP → MAP directly.",
  inputSchema: z.object({
    hostIp: z.string().default("192.168.1.10"),
    peerIp: z.string().default("192.168.1.11"),
    peerPort: z.number().default(8011),
    totalDialogs: z.number().default(100000),
    maxConcurrent: z.number().default(50000),
    ussdString: z.string().default("*100#"),
    tps: z.number().default(10000),
    durationSec: z.number().default(60),
    libPath: z.string().optional(),
  }),
  outputSchema: z.object({
    success: z.boolean(),
    stdout: z.string(),
    stderr: z.string(),
    exitCode: z.number(),
    parsedMetrics: z.object({
      tpsAchieved: z.number().optional(),
      totalRequests: z.number().optional(),
      failures: z.number().optional(),
    }).optional(),
  }),
  execute: async ({ context }) => {
    const { hostIp, peerIp, peerPort, totalDialogs, maxConcurrent, ussdString, tps, durationSec, libPath } = context;
    const lib = libPath || process.env.USSDGW_MAP_LIB || "/opt/ussdgw-test/map-level/lib";

    const cmd = [
      `java -cp "${lib}/*"`,
      "org.mobicents.protocols.ss7.map.load.ussd.Client",
      totalDialogs, maxConcurrent, "SCTP", hostIp, peerIp, peerPort,
      "IPSP", "101", "1", "2", "147", "101", "8",
      `"${ussdString}"`, "UTF-8", "0", "5000", tps, "0"
    ].join(" ");

    try {
      const stdout = execSync(cmd, {
        timeout: (durationSec + 30) * 1000,
        encoding: "utf-8",
        maxBuffer: 10 * 1024 * 1024,
      });

      const tpsMatch = stdout.match(/TPS[:\s]+([0-9.]+)/i);
      const reqMatch = stdout.match(/Total Requests[:\s]+([0-9]+)/i);
      const failMatch = stdout.match(/Failures[:\s]+([0-9]+)/i);

      return {
        success: true, stdout, stderr: "", exitCode: 0,
        parsedMetrics: {
          tpsAchieved: tpsMatch ? parseFloat(tpsMatch[1]) : undefined,
          totalRequests: reqMatch ? parseInt(reqMatch[1]) : undefined,
          failures: failMatch ? parseInt(failMatch[1]) : undefined,
        },
      };
    } catch (err: any) {
      return {
        success: false,
        stdout: err.stdout || "",
        stderr: err.stderr || err.message || "",
        exitCode: err.status || 1,
      };
    }
  },
});
