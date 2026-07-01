import { execSync } from "child_process";
import { existsSync, statSync } from "fs";

/** Build a descriptive pcap filename */
export function buildPcapFilename(
  scenario: string,
  timestamp?: string,
): string {
  const ts =
    timestamp || new Date().toISOString().replace(/[:.]/g, "-");
  return `/tmp/ussd-${scenario}-${ts}.pcap`;
}

/** Get pcap file stats */
export function getPcapStats(
  filepath: string,
): { size: number; sizeHuman: string; exists: boolean } {
  const exists = existsSync(filepath);
  if (!exists) return { size: 0, sizeHuman: "0 B", exists: false };
  const stat = statSync(filepath);
  const k = 1024;
  const sizes = ["B", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(stat.size) / Math.log(k));
  return {
    size: stat.size,
    sizeHuman:
      parseFloat((stat.size / Math.pow(k, i)).toFixed(2)) + " " + sizes[i],
    exists: true,
  };
}

/** Analyze pcap summary using capinfos or tcpdump -r */
export function analyzePcapSummary(
  filepath: string,
): { packets: number; duration: string; raw: string } {
  if (!existsSync(filepath))
    return { packets: 0, duration: "N/A", raw: "File not found" };

  // Try capinfos first (from wireshark-common)
  try {
    const out = execSync(`capinfos -c -d "${filepath}" 2>/dev/null`, {
      timeout: 10000,
      encoding: "utf-8",
    });
    const pktMatch = out.match(/Number of packets:\s*(\d+)/);
    const durMatch = out.match(/Capture duration:\s*(.+)/);
    return {
      packets: pktMatch ? parseInt(pktMatch[1]) : 0,
      duration: durMatch ? durMatch[1].trim() : "unknown",
      raw: out.trim(),
    };
  } catch {
    // Fallback to tcpdump
    try {
      const out = execSync(`tcpdump -r "${filepath}" 2>&1 | wc -l`, {
        timeout: 30000,
        encoding: "utf-8",
      });
      return {
        packets: parseInt(out.trim()) || 0,
        duration: "use capinfos for duration",
        raw: out.trim(),
      };
    } catch (err: any) {
      return {
        packets: 0,
        duration: "N/A",
        raw: err.stderr || err.message || "Error",
      };
    }
  }
}
