/**
 * SSH driver for running rlm on a remote host.
 *
 * Runs `rlm` via SSH: `ssh user@host "rlm 'query'"`
 * If context is provided, pipes it via stdin over SSH.
 *
 * Prerequisites:
 * - SSH access to the host (key-based auth recommended)
 * - `rlm` installed on the remote host (on PATH)
 * - OPENROUTER_API_KEY set on the remote host
 */

import type { Driver, DriverOptions, RlmResult } from "./types.js";
import { spawnWithTimeout } from "./spawn-helper.js";

export class SshDriver implements Driver {
  private host: string;
  private model: string | undefined;

  constructor(host: string, options?: { model?: string }) {
    this.host = host;
    this.model = options?.model;
  }

  async call(query: string, context?: string, options?: DriverOptions): Promise<RlmResult> {
    const timeout = options?.timeout ?? 300_000; // 5 minutes default
    const maxIterations = options?.maxIterations ?? 15;
    const maxDepth = options?.maxDepth ?? 3;

    const escapedQuery = query.replace(/'/g, "'\\''");

    const envParts: string[] = [
      `RLM_MAX_ITERATIONS=${maxIterations}`,
      `RLM_MAX_DEPTH=${maxDepth}`,
    ];
    if (this.model) {
      envParts.push(`RLM_MODEL='${this.model.replace(/'/g, "'\\''")}'`);
    }
    const envPrefix = envParts.join(" ");

    const remoteCmd = `${envPrefix} rlm '${escapedQuery}'`;

    const sshArgs = [
      this.host,
      "-o", "StrictHostKeyChecking=no",
      "-o", "ConnectTimeout=10",
      remoteCmd,
    ];

    const result = await spawnWithTimeout("ssh", sshArgs, {
      stdin: context,
      timeout,
    });

    return {
      answer: result.stdout.trim(),
      exitCode: result.exitCode,
      wallTimeMs: result.wallTimeMs,
      trace: `ssh://${this.host}`, // Remote trace path (not directly accessible)
    };
  }
}
