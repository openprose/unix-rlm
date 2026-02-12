/**
 * Driver interface for invoking rlm on different platforms.
 *
 * The eval harness is platform-agnostic. Drivers are the adapters that
 * invoke rlm in a specific environment (local subprocess, SSH, sprite, etc.).
 */

export interface DriverOptions {
  maxIterations?: number;
  maxDepth?: number;
  timeout?: number; // milliseconds
}

export interface RlmResult {
  answer: string;
  exitCode: number;
  wallTimeMs: number;
  trace: string; // path to workdir for post-hoc analysis
  iterations?: number; // parsed from rlm stderr metadata
}

export interface Driver {
  call(query: string, context?: string, options?: DriverOptions): Promise<RlmResult>;
}

/**
 * Result structure for a single eval task.
 */
export interface EvalResult {
  taskId: string;
  query: string;
  expectedAnswer: string;
  generatedAnswer: string;
  score: number;
  iterations: number;
  wallTimeMs: number;
  error?: string;
  trace?: string; // path to workdir for post-hoc analysis
}

/**
 * Aggregate result structure for a benchmark run.
 */
export interface BenchmarkResult {
  benchmark: string; // "s-niah" | "oolong"
  model: string; // e.g. "anthropic/claude-sonnet-4"
  config: {
    driver: string;
    maxIterations: number;
    maxDepth: number;
    concurrency: number;
  };
  timestamp: string;
  results: EvalResult[];
  aggregate: {
    meanScore: number;
    medianScore: number;
    stdScore: number;
    p25Score: number;
    p75Score: number;
    meanIterations: number;
    medianIterations: number;
    meanWallTimeMs: number;
    totalWallTimeMs: number;
    completedTasks: number;
    failedTasks: number;
  };
}
