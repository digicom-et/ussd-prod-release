import { createTool } from "@mastra/core/tools";
import { z } from "zod";
import { execSync } from "child_process";
import { existsSync, mkdirSync } from "fs";

const SESSION_NAME = "ussd-e2e-test";
const LOG_DIR = "/tmp/ussd-logs";

if (!existsSync(LOG_DIR)) {
  mkdirSync(LOG_DIR, { recursive: true });
}

function run(cmd: string, timeoutMs = 30000): { stdout: string; stderr: string; success: boolean } {
  try {
    const stdout = execSync(cmd, {
      timeout: timeoutMs,
      encoding: "utf-8",
      maxBuffer: 16 * 1024 * 1024,
    });
    return { stdout: stdout.trim(), stderr: "", success: true };
  } catch (err: any) {
    return {
      stdout: (err.stdout || "").trim(),
      stderr: (err.stderr || err.message || "").trim(),
      success: false,
    };
  }
}

export const tmuxSessionManager = createTool({
  id: "tmux-session-manager",
  description:
    "Manage tmux sessions for USSD e2e testing. Creates detached tmux sessions with named windows running test processes, pipes output to log files, and waits for health checks.",
  inputSchema: z.object({
    action: z.enum([
      "createSession",
      "createWindow",
      "sendKeys",
      "captureOutput",
      "waitForPattern",
      "waitForPort",
      "killSession",
      "listWindows",
      "killWindow",
      "waitForHealth",
    ]),
    sessionName: z.string().optional().default(SESSION_NAME),
    windowName: z.string().optional(),
    command: z.string().optional(),
    keys: z.string().optional(),
    lines: z.number().optional().default(50),
    pattern: z.string().optional(),
    host: z.string().optional().default("localhost"),
    port: z.number().optional(),
    timeoutMs: z.number().optional().default(60000),
    healthUrl: z.string().optional(),
  }),
  outputSchema: z.object({
    success: z.boolean(),
    stdout: z.string(),
    stderr: z.string(),
    details: z.string().optional(),
  }),
  execute: async ({ context }) => {
    const {
      action,
      sessionName = SESSION_NAME,
      windowName = "",
      command = "",
      keys = "",
      lines = 50,
      pattern = "",
      host = "localhost",
      port = 0,
      timeoutMs = 60000,
      healthUrl = "",
    } = context;

    switch (action) {

      case "createSession": {
        run(`tmux kill-session -t "${sessionName}" 2>/dev/null`, 5000);
        const r = run(
          `tmux new-session -d -s "${sessionName}" -n "preflight"`,
          10000,
        );
        return {
          success: r.success,
          stdout: r.stdout || `Session "${sessionName}" created`,
          stderr: r.stderr,
          details: `Attach: tmux attach -t ${sessionName}`,
        };
      }

      case "createWindow": {
        if (!windowName || !command) {
          return { success: false, stdout: "", stderr: "windowName and command required" };
        }
        const logFile = `${LOG_DIR}/${windowName}.log`;
        run(`: > "${logFile}"`, 5000);
        const fullCmd =
          `tmux new-window -t "${sessionName}" -n "${windowName}" ` +
          `'${command} 2>&1 | tee "${logFile}"'`;
        const r = run(fullCmd, 15000);
        return {
          success: r.success,
          stdout: r.stdout || `Window "${windowName}" created`,
          stderr: r.stderr,
          details: `Log: ${logFile}`,
        };
      }

      case "sendKeys": {
        if (!windowName || !keys) {
          return { success: false, stdout: "", stderr: "windowName and keys required" };
        }
        const escaped = keys.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        const r = run(
          `tmux send-keys -t "${sessionName}:${windowName}" "${escaped}" Enter`,
          10000,
        );
        return {
          success: r.success,
          stdout: r.stdout,
          stderr: r.stderr,
          details: r.success ? `Sent to ${sessionName}:${windowName}` : `Failed: ${r.stderr}`,
        };
      }

      case "captureOutput": {
        if (!windowName) {
          return { success: false, stdout: "", stderr: "windowName required" };
        }
        const logFile = `${LOG_DIR}/${windowName}.log`;
        if (existsSync(logFile)) {
          const tailR = run(`tail -n ${lines} "${logFile}" 2>/dev/null`, 5000);
          if (tailR.success && tailR.stdout) {
            return {
              success: true, stdout: tailR.stdout, stderr: "",
              details: `Last ${lines} lines from ${logFile}`,
            };
          }
        }
        const r = run(
          `tmux capture-pane -t "${sessionName}:${windowName}" -p -S -${lines} 2>/dev/null`,
          5000,
        );
        return {
          success: r.success, stdout: r.stdout, stderr: r.stderr,
          details: r.success ? `Last ${lines} lines from pane` : `Failed: ${r.stderr}`,
        };
      }

      case "waitForPattern": {
        if (!windowName || !pattern) {
          return { success: false, stdout: "", stderr: "windowName and pattern required" };
        }
        const logFile = `${LOG_DIR}/${windowName}.log`;
        const start = Date.now();
        while (Date.now() - start < timeoutMs) {
          if (existsSync(logFile)) {
            const gr = run(
              `grep -qF "${pattern.replace(/"/g, '\\"')}" "${logFile}" 2>/dev/null && echo FOUND || echo NF`,
              5000,
            );
            if (gr.stdout.includes("FOUND")) {
              const ml = run(
                `grep -F "${pattern.replace(/"/g, '\\"')}" "${logFile}" | tail -1`,
                5000,
              );
              return {
                success: true, stdout: ml.stdout, stderr: "",
                details: `Pattern found after ${Date.now() - start}ms`,
              };
            }
          }
          const pr = run(
            `tmux capture-pane -t "${sessionName}:${windowName}" -p -S -100 2>/dev/null`,
            5000,
          );
          if (pr.stdout.includes(pattern)) {
            return {
              success: true, stdout: pr.stdout, stderr: "",
              details: `Pattern found in pane after ${Date.now() - start}ms`,
            };
          }
          run("sleep 1", 2000);
        }
        return {
          success: false, stdout: "", stderr: `Timeout waiting for "${pattern}"`,
          details: `Waited ${timeoutMs}ms`,
        };
      }

      case "waitForPort": {
        if (!port) {
          return { success: false, stdout: "", stderr: "port required" };
        }
        const start = Date.now();
        while (Date.now() - start < timeoutMs) {
          const cr = run(
            `timeout 3 bash -c "echo >/dev/tcp/${host}/${port}" 2>&1 && echo OPEN || echo CLOSED`,
            5000,
          );
          if (cr.stdout.includes("OPEN")) {
            return {
              success: true, stdout: `Port ${host}:${port} open`, stderr: "",
              details: `Available after ${Date.now() - start}ms`,
            };
          }
          run("sleep 2", 3000);
        }
        return {
          success: false, stdout: "", stderr: `Timeout waiting for ${host}:${port}`,
          details: `Waited ${timeoutMs}ms`,
        };
      }

      case "waitForHealth": {
        if (!healthUrl) {
          return { success: false, stdout: "", stderr: "healthUrl required" };
        }
        const start = Date.now();
        while (Date.now() - start < timeoutMs) {
          const cr = run(
            `curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "${healthUrl}" 2>/dev/null || echo "000"`,
            10000,
          );
          const code = parseInt(cr.stdout, 10);
          if (code >= 200 && code < 500) {
            return {
              success: true, stdout: `Health OK (HTTP ${code})`, stderr: "",
              details: `Responded after ${Date.now() - start}ms`,
            };
          }
          run("sleep 2", 3000);
        }
        return {
          success: false, stdout: "", stderr: `Health timeout: ${healthUrl}`,
          details: `Waited ${timeoutMs}ms`,
        };
      }

      case "killSession": {
        const r = run(`tmux kill-session -t "${sessionName}" 2>/dev/null`, 10000);
        return {
          success: true,
          stdout: `Session "${sessionName}" killed`,
          stderr: r.stderr,
        };
      }

      case "killWindow": {
        if (!windowName) {
          return { success: false, stdout: "", stderr: "windowName required" };
        }
        const r = run(`tmux kill-window -t "${sessionName}:${windowName}" 2>/dev/null`, 10000);
        return {
          success: true,
          stdout: `Window "${windowName}" killed`,
          stderr: r.stderr,
        };
      }

      case "listWindows": {
        const r = run(
          `tmux list-windows -t "${sessionName}" -F '#{window_index}:#{window_name}' 2>/dev/null`,
          10000,
        );
        if (!r.success && r.stderr.includes("can't find session")) {
          return { success: false, stdout: "", stderr: `Session "${sessionName}" not found` };
        }
        return {
          success: true, stdout: r.stdout, stderr: r.stderr,
          details: `Windows:\n${r.stdout}`,
        };
      }

      default: {
        return {
          success: false, stdout: "", stderr: `Unknown action: ${action}`,
          details: "Valid: createSession, createWindow, sendKeys, captureOutput, waitForPattern, waitForPort, waitForHealth, killSession, killWindow, listWindows",
        };
      }
    }
  },
});
