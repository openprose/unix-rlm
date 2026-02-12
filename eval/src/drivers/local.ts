/** Local subprocess driver. Spawns `rlm` as a child process. */

import { existsSync, mkdtempSync, readdirSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import type { Driver, DriverOptions, RlmResult } from "./types.js";
import { spawnWithTimeout } from "./spawn-helper.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

function findRlmBinary(): string {
  // Look relative to eval directory first: eval/src/drivers -> eval -> unix-rlm/bin/rlm
  const relPath = resolve(__dirname, "..", "..", "..", "bin", "rlm");
  if (existsSync(relPath)) {
    return relPath;
  }

  // Fall back to PATH
  return "rlm";
}

export class LocalDriver implements Driver {
  private rlmPath: string;
  private treeRoot: string | undefined;
  private mockDir: string | undefined;
  private model: string | undefined;

  constructor(options?: { rlmPath?: string; treeRoot?: string; mockDir?: string; model?: string }) {
    this.rlmPath = options?.rlmPath ?? findRlmBinary();
    this.treeRoot = options?.treeRoot;
    this.mockDir = options?.mockDir;
    this.model = options?.model;
  }

  async call(query: string, context?: string, options?: DriverOptions): Promise<RlmResult> {
    const treeRoot = this.treeRoot ?? mkdtempSync(join(tmpdir(), "rlm-eval-"));
    const timeout = options?.timeout ?? 300_000; // 5 minutes default

    const env: Record<string, string> = {
      ...process.env as Record<string, string>,
      RLM_MAX_ITERATIONS: String(options?.maxIterations ?? 15),
      RLM_MAX_DEPTH: String(options?.maxDepth ?? 3),
      _RLM_TREE_ROOT: treeRoot,
    };

    if (this.mockDir) {
      env._RLM_MOCK_DIR = this.mockDir;
    }

    if (this.model) {
      env.RLM_MODEL = this.model;
    }

    const result = await spawnWithTimeout(this.rlmPath, [query], {
      env,
      stdin: context,
      timeout,
    });

    // Parse rlm-meta from stderr
    let iterations: number | undefined;
    const metaMatch = result.stderr.match(/rlm-meta: (\{.*\})/);
    if (metaMatch) {
      try {
        const meta = JSON.parse(metaMatch[1]);
        iterations = meta.iterations;
      } catch {}
    }

    // workdir is treeRoot/{PID}/
    let trace = treeRoot;
    try {
      const dirs = readdirSync(treeRoot);
      if (dirs.length > 0) {
        // Use the most recent directory (or the only one)
        trace = join(treeRoot, dirs[dirs.length - 1]);
      }
    } catch {
      // treeRoot may not exist if rlm failed early
    }

    return {
      answer: result.stdout.trim(),
      exitCode: result.exitCode,
      wallTimeMs: result.wallTimeMs,
      trace,
      iterations,
    };
  }
}
