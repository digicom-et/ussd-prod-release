import { existsSync } from "fs";
import { resolve } from "path";

/**
 * Auto-detect the USSD Gateway package root directory.
 *
 * Resolution order:
 *   1. PKG_ROOT env var (set by scripts/env.sh or user)
 *   2. Walk up from process.cwd() looking for VERSION + scripts/env.sh
 *   3. process.cwd() as last resort
 *
 * This allows users to git clone the package anywhere
 * (e.g. /home/$USER/ussdgw-prod-release, /tmp/test, etc.)
 * without hardcoding /opt paths.
 */
function findPackageRoot(): string {
  // 1. Explicit env var (scripts/env.sh sets this)
  if (process.env.PKG_ROOT) {
    return process.env.PKG_ROOT;
  }

  // 2. Walk up from cwd looking for package markers
  let dir = process.cwd();
  const root = resolve("/");
  while (dir !== root) {
    if (existsSync(`${dir}/VERSION`) && existsSync(`${dir}/scripts/env.sh`)) {
      return dir;
    }
    dir = resolve(dir, "..");
  }

  // 3. Fallback
  return process.cwd();
}

export const PKG_ROOT = findPackageRoot();
