import { createStep, createWorkflow } from "@mastra/core/workflows";
import { z } from "zod";
import { execSync } from "child_process";
import { PKG_ROOT } from "../config";

const SESSION = "ussd-e2e-test";

function run(cmd: string, timeoutMs = 30000): string {
  try {
    return execSync(cmd, { timeout: timeoutMs, encoding: "utf-8", maxBuffer: 16 * 1024 * 1024 }).trim();
  } catch (err: any) {
    return (err.stdout || err.stderr || err.message || "").trim();
  }
}

function t(action: string, windowName: string, opts: Record<string, unknown> = {}): string {
  const args = JSON.stringify({ action, sessionName: SESSION, windowName, ...opts })
    .replace(/"/g, '\\"');
  return run(`mastra call-tool tmux-session-manager "${args}"`, 120000);
}

// ─── S0: PREFLIGHT ────────────────────────────────────────────
const s0PreflightStep = createStep({
  id: "s0-preflight",
  inputSchema: z.object({
    pkgRoot: z.string().default(PKG_ROOT),
    scenarios: z.array(z.string()).default([
      "S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10"
    ]),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    preflightPassed: z.boolean(),
    preflightReport: z.string(),
  }),
  execute: async ({ inputData }) => {
    const pkgRoot = inputData.pkgRoot;
    const lines: string[] = [];
    let allPassed = true;

    // Check SCTP kernel module
    const sctp = run("lsmod | grep sctp || echo 'SCTP_NOT_LOADED'", 5000);
    if (sctp.includes("SCTP_NOT_LOADED")) {
      lines.push("[FAIL] SCTP kernel module not loaded");
      allPassed = false;
    } else {
      lines.push(`[PASS] SCTP module: ${sctp.split("\n")[0]}`);
    }

    // Check Java
    const java = run("java -version 2>&1 || echo 'JAVA_NOT_FOUND'", 5000);
    if (java.includes("JAVA_NOT_FOUND")) {
      lines.push("[FAIL] Java not found");
      allPassed = false;
    } else {
      lines.push(`[PASS] Java: ${java.split("\n")[0] || "installed"}`);
    }

    // Check Python
    const python = run("python3 --version 2>&1 || echo 'PYTHON_NOT_FOUND'", 5000);
    if (python.includes("PYTHON_NOT_FOUND")) {
      lines.push("[FAIL] Python3 not found");
      allPassed = false;
    } else {
      lines.push(`[PASS] Python: ${python}`);
    }

    // Check Docker
    const docker = run("docker info 2>&1 | head -5 || echo 'DOCKER_NOT_FOUND'", 5000);
    if (docker.includes("DOCKER_NOT_FOUND")) {
      lines.push("[FAIL] Docker not accessible");
      allPassed = false;
    } else {
      lines.push("[PASS] Docker: available");
    }

    // Check PKG_ROOT exists
    const pkgCheck = run(`test -d "${pkgRoot}" && echo EXISTS || echo NOT_FOUND`, 3000);
    if (pkgCheck.includes("NOT_FOUND")) {
      lines.push(`[FAIL] PKG_ROOT ${pkgRoot} not found`);
      allPassed = false;
    } else {
      lines.push(`[PASS] PKG_ROOT: ${pkgRoot}`);
    }

    const report = lines.join("\n");
    return { pkgRoot, scenarios: inputData.scenarios, preflightPassed: allPassed, preflightReport: report };
  },
});

// ─── S1: LOAD DOCKER IMAGE ────────────────────────────────────
const s1LoadDockerStep = createStep({
  id: "s1-load-docker",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    preflightPassed: z.boolean(),
    preflightReport: z.string(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    preflightPassed: z.boolean(),
    dockerLoaded: z.boolean(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S1")) {
      return { ...inputData, dockerLoaded: true };
    }
    const script = `${pkgRoot}/scripts/01-load-docker-image.sh`;
    const out = run(`bash "${script}" 2>&1`, 300000);
    const success = !out.toLowerCase().includes("error") && !out.toLowerCase().includes("failed");
    return { ...inputData, dockerLoaded: success };
  },
});

// ─── S2: SETUP HOST ───────────────────────────────────────────
const s2SetupHostStep = createStep({
  id: "s2-setup-host",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    dockerLoaded: z.boolean(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    hostSetup: z.boolean(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S2")) {
      return { ...inputData, hostSetup: true };
    }
    const script = `${pkgRoot}/scripts/02-setup-host.sh`;
    const out = run(`sudo bash "${script}" 2>&1`, 60000);
    const success = !out.toLowerCase().includes("error");
    return { ...inputData, hostSetup: success };
  },
});

// ─── S3: START GATEWAY (tmux) ─────────────────────────────────
const s3StartGatewayStep = createStep({
  id: "s3-start-gateway",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    hostSetup: z.boolean(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    gatewayStarted: z.boolean(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S3")) {
      return { ...inputData, gatewayStarted: true };
    }
    // Create tmux session and window for docker compose
    run(`tmux kill-session -t "${SESSION}" 2>/dev/null`, 3000);
    run(`tmux new-session -d -s "${SESSION}" -n "docker-gw"`, 5000);
    const composeDir = `${pkgRoot}/gateway`;
    run(
      `tmux send-keys -t "${SESSION}:docker-gw" ` +
      `'docker compose -f ${composeDir}/docker-compose.yml up 2>&1 | tee /tmp/ussd-logs/docker-gw.log' Enter`,
      5000,
    );
    // Wait for Jolokia health endpoint
    const start = Date.now();
    let healthy = false;
    while (Date.now() - start < 120000) {
      const curlOut = run(
        "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 http://localhost:8080/jolokia/version 2>/dev/null || echo '000'",
        10000,
      );
      if (curlOut !== "000" && parseInt(curlOut, 10) >= 200) {
        healthy = true;
        break;
      }
      run("sleep 3", 4000);
    }
    return { ...inputData, gatewayStarted: healthy };
  },
});

// ─── S4: START gRPC AS ────────────────────────────────────────
const s4StartGrpcAsStep = createStep({
  id: "s4-start-grpc-as",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    gatewayStarted: z.boolean(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    grpcAsStarted: z.boolean(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S4")) {
      return { ...inputData, grpcAsStarted: true };
    }
    const asDir = `${pkgRoot}/grpc-as-tester`;
    run(
      `tmux new-window -t "${SESSION}" -n "grpc-as" ` +
      `'cd ${asDir} && python3 ussd_as_server.py --port 8443 2>&1 | tee /tmp/ussd-logs/grpc-as.log'`,
      10000,
    );
    // Wait for "listening on :8443"
    const start = Date.now();
    let ready = false;
    while (Date.now() - start < 30000) {
      const out = run("grep -q 'listening on :8443' /tmp/ussd-logs/grpc-as.log 2>/dev/null && echo FOUND || echo NF", 5000);
      if (out.includes("FOUND")) { ready = true; break; }
      run("sleep 1", 2000);
    }
    return { ...inputData, grpcAsStarted: ready };
  },
});

// ─── S5: MAP SMOKE ────────────────────────────────────────────
const s5MapSmokeStep = createStep({
  id: "s5-map-smoke",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    grpcAsStarted: z.boolean(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    mapSmokeResult: z.string(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S5")) {
      return { ...inputData, mapSmokeResult: "SKIPPED" };
    }
    const mapDir = `${pkgRoot}/tools/jss7-map-load`;
    const cmd = `cd ${mapDir} && java -cp "lib/*" Client 10 '*100# BALANCE' 2>&1 | tee /tmp/ussd-logs/map-smoke.log`;
    run(`tmux new-window -t "${SESSION}" -n "map-smoke" '${cmd}'`, 10000);
    const start = Date.now();
    let done = false;
    while (Date.now() - start < 120000) {
      const out = run("tail -20 /tmp/ussd-logs/map-smoke.log 2>/dev/null", 3000);
      if (out.includes("SUMMARY") || out.includes("PASS") || out.includes("FAIL")) {
        done = true;
        break;
      }
      run("sleep 2", 3000);
    }
    const lastOut = run("tail -30 /tmp/ussd-logs/map-smoke.log 2>/dev/null", 5000);
    return { ...inputData, mapSmokeResult: done ? lastOut : "TIMEOUT" };
  },
});

// ─── S6: gRPC SMOKE ───────────────────────────────────────────
const s6GrpcSmokeStep = createStep({
  id: "s6-grpc-smoke",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    mapSmokeResult: z.string(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    grpcSmokeResult: z.string(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S6")) {
      return { ...inputData, grpcSmokeResult: "SKIPPED" };
    }
    const asDir = `${pkgRoot}/grpc-as-tester`;
    const cmd =
      `cd ${asDir} && python3 loadtest_client.py --target localhost:8443 --tps 50 --duration 30 --multi-menu ` +
      `2>&1 | tee /tmp/ussd-logs/grpc-smoke.log`;
    run(`tmux new-window -t "${SESSION}" -n "grpc-smoke" '${cmd}'`, 10000);
    // Wait up to 90s for completion
    const start = Date.now();
    while (Date.now() - start < 90000) {
      const out = run("tail -5 /tmp/ussd-logs/grpc-smoke.log 2>/dev/null", 3000);
      if (out.includes("SUMMARY") || out.includes("=== ") || out.includes("Total")) break;
      run("sleep 2", 3000);
    }
    const lastOut = run("tail -30 /tmp/ussd-logs/grpc-smoke.log 2>/dev/null", 5000);
    return { ...inputData, grpcSmokeResult: lastOut };
  },
});

// ─── S7: gRPC PUSH SMOKE ──────────────────────────────────────
const s7GrpcPushStep = createStep({
  id: "s7-grpc-push",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    grpcSmokeResult: z.string(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    grpcPushResult: z.string(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S7")) {
      return { ...inputData, grpcPushResult: "SKIPPED" };
    }
    const asDir = `${pkgRoot}/grpc-as-tester`;
    const cmd =
      `cd ${asDir} && python3 grpc_push_client.py --target localhost:8453 --mode multi ` +
      `2>&1 | tee /tmp/ussd-logs/grpc-push.log`;
    run(`tmux new-window -t "${SESSION}" -n "grpc-push" '${cmd}'`, 10000);
    const start = Date.now();
    while (Date.now() - start < 90000) {
      const out = run("tail -5 /tmp/ussd-logs/grpc-push.log 2>/dev/null", 3000);
      if (out.includes("SUMMARY") || out.includes("=== ") || out.includes("Total")) break;
      run("sleep 2", 3000);
    }
    const lastOut = run("tail -30 /tmp/ussd-logs/grpc-push.log 2>/dev/null", 5000);
    return { ...inputData, grpcPushResult: lastOut };
  },
});

// ─── S8: HTTP PULL ────────────────────────────────────────────
const s8HttpPullStep = createStep({
  id: "s8-http-pull",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    grpcPushResult: z.string(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    httpPullResult: z.string(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S8")) {
      return { ...inputData, httpPullResult: "SKIPPED" };
    }
    // Start HTTP AS server in tmux window
    const asDir = `${pkgRoot}/http-as-tester`;
    run(
      `tmux new-window -t "${SESSION}" -n "http-as" ` +
      `'cd ${asDir} && python3 http_as_server.py :8049 2>&1 | tee /tmp/ussd-logs/http-as.log'`,
      10000,
    );
    // Wait for HTTP server
    run("sleep 3", 5000);
    // Run MAP test with *519# 
    const mapDir = `${pkgRoot}/tools/jss7-map-load`;
    const cmd =
      `cd ${mapDir} && java -cp "lib/*" Client 10 '*519# BALANCE' ` +
      `2>&1 | tee /tmp/ussd-logs/http-pull.log`;
    run(`tmux new-window -t "${SESSION}" -n "http-pull" '${cmd}'`, 10000);
    const start = Date.now();
    while (Date.now() - start < 120000) {
      const out = run("tail -5 /tmp/ussd-logs/http-pull.log 2>/dev/null", 3000);
      if (out.includes("SUMMARY") || out.includes("PASS") || out.includes("FAIL")) break;
      run("sleep 2", 3000);
    }
    const lastOut = run("tail -30 /tmp/ussd-logs/http-pull.log 2>/dev/null", 5000);
    return { ...inputData, httpPullResult: lastOut };
  },
});

// ─── S9: HTTP PUSH ────────────────────────────────────────────
const s9HttpPushStep = createStep({
  id: "s9-http-push",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    httpPullResult: z.string(),
  }),
  outputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    httpPushResult: z.string(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S9")) {
      return { ...inputData, httpPushResult: "SKIPPED" };
    }
    const asDir = `${pkgRoot}/http-as-tester`;
    const cmd =
      `cd ${asDir} && python3 http_push_loadtest.py 2>&1 | tee /tmp/ussd-logs/http-push.log`;
    run(`tmux new-window -t "${SESSION}" -n "http-push" '${cmd}'`, 10000);
    const start = Date.now();
    while (Date.now() - start < 120000) {
      const out = run("tail -5 /tmp/ussd-logs/http-push.log 2>/dev/null", 3000);
      if (out.includes("SUMMARY") || out.includes("=== ") || out.includes("Total")) break;
      run("sleep 2", 3000);
    }
    const lastOut = run("tail -30 /tmp/ussd-logs/http-push.log 2>/dev/null", 5000);
    return { ...inputData, httpPushResult: lastOut };
  },
});

// ─── S10: STOP ALL ────────────────────────────────────────────
const s10StopAllStep = createStep({
  id: "s10-stop-all",
  inputSchema: z.object({
    pkgRoot: z.string(),
    scenarios: z.array(z.string()),
    httpPushResult: z.string(),
  }),
  outputSchema: z.object({
    scenarios: z.array(z.string()),
    stopReport: z.string(),
    tmuxSessionLeft: z.string(),
  }),
  execute: async ({ inputData }) => {
    const { pkgRoot } = inputData;
    if (!inputData.scenarios.includes("S10")) {
      return { ...inputData, stopReport: "SKIPPED", tmuxSessionLeft: SESSION };
    }
    const lines: string[] = [];
    lines.push("Stopping all test processes...");

    // Kill python servers
    run("pkill -f ussd_as_server.py 2>/dev/null; pkill -f http_as_server.py 2>/dev/null; pkill -f loadtest_client.py 2>/dev/null; pkill -f grpc_push_client.py 2>/dev/null; pkill -f http_push_loadtest.py 2>/dev/null; echo 'Python processes killed'", 10000);
    lines.push("[OK] Python test processes killed");

    // Docker compose down
    const composeDir = `${pkgRoot}/gateway`;
    const dcOut = run(`docker compose -f ${composeDir}/docker-compose.yml down 2>&1`, 60000);
    lines.push(`[OK] Docker compose down: ${dcOut.substring(0, 100)}`);

    // Log tmux windows before keeping them
    lines.push(`Tmux session "${SESSION}" left open for inspection.`);
    lines.push(`Attach with: tmux attach -t ${SESSION}`);

    const stopReport = lines.join("\n");
    return { ...inputData, stopReport, tmuxSessionLeft: SESSION };
  },
});

// ─── MAIN WORKFLOW ────────────────────────────────────────────
export const scenarioRunner = createWorkflow({
  id: "scenario-runner",
  inputSchema: z.object({
    scenarios: z.array(z.string()).default([
      "S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10",
    ]),
    pkgRoot: z.string().default(PKG_ROOT),
    pcap: z.boolean().default(false),
  }),
  outputSchema: z.object({
    scenarios: z.array(z.string()),
    preflightPassed: z.boolean(),
    gatewayStarted: z.boolean(),
    grpcAsStarted: z.boolean(),
    mapSmokeResult: z.string(),
    grpcSmokeResult: z.string(),
    grpcPushResult: z.string(),
    httpPullResult: z.string(),
    httpPushResult: z.string(),
    stopReport: z.string(),
    tmuxSessionLeft: z.string(),
  }),
})
  .then(s0PreflightStep)
  .then(s1LoadDockerStep)
  .then(s2SetupHostStep)
  .then(s3StartGatewayStep)
  .then(s4StartGrpcAsStep)
  .then(s5MapSmokeStep)
  .then(s6GrpcSmokeStep)
  .then(s7GrpcPushStep)
  .then(s8HttpPullStep)
  .then(s9HttpPushStep)
  .then(s10StopAllStep)
  .commit();
