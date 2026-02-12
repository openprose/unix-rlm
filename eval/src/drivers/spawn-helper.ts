/** Shared spawn+collect+timeout helper for local and SSH drivers. */

import { spawn } from "node:child_process";

export interface SpawnOptions {
	env?: Record<string, string>;
	stdin?: string;
	timeout: number; // milliseconds
}

export interface SpawnResult {
	stdout: string;
	stderr: string;
	exitCode: number;
	wallTimeMs: number;
}

/**
 * Spawn a child process, collect stdout/stderr, enforce a timeout, and
 * return the collected output.  SIGTERM is sent on timeout, followed by
 * SIGKILL 1 second later.
 */
export function spawnWithTimeout(
	cmd: string,
	args: string[],
	opts: SpawnOptions,
): Promise<SpawnResult> {
	const start = Date.now();

	return new Promise<SpawnResult>((resolve) => {
		const child = spawn(cmd, args, {
			env: opts.env,
			stdio: ["pipe", "pipe", "pipe"],
		});

		let stdout = "";
		let stderr = "";

		child.stdout.on("data", (data: Buffer) => {
			stdout += data.toString();
		});

		child.stderr.on("data", (data: Buffer) => {
			stderr += data.toString();
		});

		if (opts.stdin !== undefined) {
			child.stdin.write(opts.stdin);
		}
		child.stdin.end();

		const timer = setTimeout(() => {
			child.kill("SIGTERM");
			setTimeout(() => child.kill("SIGKILL"), 1000);
		}, opts.timeout);

		child.on("close", (code: number | null) => {
			clearTimeout(timer);
			resolve({
				stdout,
				stderr,
				exitCode: code ?? 1,
				wallTimeMs: Date.now() - start,
			});
		});

		child.on("error", (_err: Error) => {
			clearTimeout(timer);
			resolve({
				stdout: "",
				stderr: "",
				exitCode: 1,
				wallTimeMs: Date.now() - start,
			});
		});
	});
}
