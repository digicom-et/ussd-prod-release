import { createTool } from "@mastra/core/tools";
import { z } from "zod";
import { execSync } from "child_process";
import { existsSync, statSync, readFileSync, unlinkSync } from "fs";

/**
 * PCAP Capture Tool — wraps tcpdump for packet capture during e2e tests.
 * Supports SCTP (proto 132), TCP port filter, or all traffic.
 */
export const pcapCapture = createTool({
  id: "pcap-capture",
  description: "Capture network packets during e2e tests using tcpdump. Supports SCTP, TCP, and all traffic with port/protocol filters.",
  inputSchema: z.object({
    action: z.enum(["start", "stop", "status"]),
    interface: z.string().default("any"),
    portFilter: z.string().optional(),
    protocol: z.enum(["sctp", "tcp", "all"]).default("all"),
    outputFile: z.string().optional(),
    scenario: z.string().optional(),
  }),
  outputSchema: z.object({
    success: z.boolean(),
    action: z.string(),
    pid: z.number().optional(),
    outputFile: z.string().optional(),
    command: z.string().optional(),
    fileSize: z.number().optional(),
    fileSizeHuman: z.string().optional(),
    running: z.boolean().optional(),
    error: z.string().optional(),
  }),
  execute: async ({ context }) => {
    const pidFile = "/tmp/ussd-pcap.pid";
    const defaultOutput = `/tmp/ussd-e2e-${context.scenario || Date.now()}.pcap`;
    const outputFile = context.outputFile || defaultOutput;

    // Check tcpdump available
    try {
      execSync("which tcpdump", { timeout: 5000, encoding: "utf-8" });
    } catch {
      return {
        success: false,
        action: context.action,
        error: "tcpdump not installed. Install: sudo apt-get install tcpdump (Debian/Ubuntu) or sudo yum install tcpdump (RHEL/CentOS)",
      };
    }

    // START
    if (context.action === "start") {
      // Check if already running
      if (existsSync(pidFile)) {
        const oldPid = parseInt(readFileSync(pidFile, "utf-8").trim());
        try {
          process.kill(oldPid, 0);
        } catch {
          unlinkSync(pidFile);
        }
        if (existsSync(pidFile)) {
          return {
            success: false,
            action: "start",
            error: `tcpdump already running (PID ${oldPid}). Stop it first or use action=stop.`,
          };
        }
      }

      let filter = "";
      if (context.protocol === "sctp") {
        filter = "proto 132";
      } else if (context.protocol === "tcp" && context.portFilter) {
        filter = `tcp port ${context.portFilter}`;
      } else if (context.protocol === "tcp") {
        filter = "tcp";
      }

      const cmd = `nohup tcpdump -i ${context.interface} -s 0 -w ${outputFile} ${filter} > /tmp/ussd-pcap-stdout.log 2>&1 & echo $!`;

      try {
        const pid = parseInt(
          execSync(cmd, { timeout: 10000, encoding: "utf-8" }).trim(),
        );
        execSync(`echo ${pid} > ${pidFile}`, { timeout: 5000 });
        return {
          success: true,
          action: "start",
          pid,
          outputFile,
          command: `tcpdump -i ${context.interface} -s 0 -w ${outputFile} ${filter}`.trim(),
        };
      } catch (err: any) {
        const stderr = err.stderr || err.message || "";
        if (
          stderr.includes("Permission denied") ||
          stderr.includes("Operation not permitted")
        ) {
          return {
            success: false,
            action: "start",
            error:
              "Permission denied. Run with sudo or: sudo setcap cap_net_raw,cap_net_admin=eip $(which tcpdump)",
          };
        }
        return { success: false, action: "start", error: stderr };
      }
    }

    // STOP
    if (context.action === "stop") {
      if (!existsSync(pidFile)) {
        return {
          success: false,
          action: "stop",
          error: "No tcpdump running (PID file not found)",
        };
      }

      const pid = parseInt(readFileSync(pidFile, "utf-8").trim());
      try {
        process.kill(pid, "SIGTERM");
        // Wait a moment for tcpdump to flush
        execSync("sleep 1", { timeout: 5000 });
      } catch (e) {
        /* may already be dead */
      }

      // Clean up PID file
      try {
        unlinkSync(pidFile);
      } catch {}

      if (existsSync(outputFile)) {
        const stat = statSync(outputFile);
        return {
          success: true,
          action: "stop",
          outputFile,
          fileSize: stat.size,
          fileSizeHuman: formatBytes(stat.size),
        };
      }
      return {
        success: true,
        action: "stop",
        outputFile,
        fileSize: 0,
        fileSizeHuman: "0 B",
      };
    }

    // STATUS
    if (context.action === "status") {
      let running = false;
      let pid = 0;
      if (existsSync(pidFile)) {
        pid = parseInt(readFileSync(pidFile, "utf-8").trim());
        try {
          process.kill(pid, 0);
          running = true;
        } catch {
          running = false;
        }
      }

      let fileSize = 0;
      let fileSizeHuman = "0 B";
      if (existsSync(outputFile)) {
        fileSize = statSync(outputFile).size;
        fileSizeHuman = formatBytes(fileSize);
      }

      return {
        success: true,
        action: "status",
        running,
        pid: running ? pid : undefined,
        outputFile,
        fileSize,
        fileSizeHuman,
      };
    }

    return { success: false, action: context.action, error: "Unknown action" };
  },
});

function formatBytes(bytes: number): string {
  if (bytes === 0) return "0 B";
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
}
