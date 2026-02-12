/**
 * Eval harness: concurrent task runner with resumability and progress
 * reporting.
 *
 * Ported from the JS RLM eval suite, adapted for the bash rlm.
 */

import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import type { Driver, DriverOptions, EvalResult, BenchmarkResult } from "./drivers/types.js";
import type { EvalTask } from "./datasets/s-niah.js";
import { sorted, mean, median, percentile, std } from "./stats.js";

export type ScoringFn = (expected: string, actual: string) => number;

export interface HarnessOptions {
  driver: Driver;
  scoringFn: ScoringFn;
  driverOptions: DriverOptions;
  concurrency: number;
  outputPath: string;
  benchmark: string;
  model: string;
  driverName: string;
  onProgress?: (progress: ProgressInfo) => void;
}

export interface ProgressInfo {
  completed: number;
  total: number;
  score: number;
  meanScore: number;
  elapsed: string;
}

/**
 * Count iterations from a trace directory path.
 * Reads the trace/ subdirectory and counts *-response.md files.
 */
function countIterations(tracePath: string): number {
  try {
    const traceDir = join(tracePath, "trace");
    const files = readdirSync(traceDir);
    return files.filter((f: string) => f.endsWith("-response.md")).length;
  } catch {
    return 0;
  }
}

function formatElapsed(ms: number): string {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) {
    return `${hours}h${String(minutes % 60).padStart(2, "0")}m`;
  }
  if (minutes > 0) {
    return `${minutes}m${String(seconds % 60).padStart(2, "0")}s`;
  }
  return `${seconds}s`;
}

function computeAggregate(results: EvalResult[]): BenchmarkResult["aggregate"] {
  const completed = results.filter((r) => !r.error);
  const failed = results.filter((r) => !!r.error);

  const scores = completed.map((r) => r.score);
  const iterations = completed.map((r) => r.iterations);
  const wallTimes = completed.map((r) => r.wallTimeMs);

  return {
    meanScore: mean(scores),
    medianScore: median(scores),
    stdScore: std(scores),
    p25Score: percentile(scores, 25),
    p75Score: percentile(scores, 75),
    meanIterations: mean(iterations),
    medianIterations: median(iterations),
    meanWallTimeMs: mean(wallTimes),
    totalWallTimeMs: wallTimes.reduce((a, b) => a + b, 0),
    completedTasks: completed.length,
    failedTasks: failed.length,
  };
}

function loadExistingResults(outputPath: string): Map<string, EvalResult> {
  const map = new Map<string, EvalResult>();
  if (!existsSync(outputPath)) {
    return map;
  }
  try {
    const data = JSON.parse(readFileSync(outputPath, "utf-8")) as BenchmarkResult;
    for (const result of data.results) {
      map.set(result.taskId, result);
    }
  } catch {
    // File exists but is corrupt or empty; start fresh
  }
  return map;
}

function saveResults(options: HarnessOptions, results: EvalResult[]): BenchmarkResult {
  const benchmarkResult: BenchmarkResult = {
    benchmark: options.benchmark,
    model: options.model,
    config: {
      driver: options.driverName,
      maxIterations: options.driverOptions.maxIterations ?? 15,
      maxDepth: options.driverOptions.maxDepth ?? 2,
      concurrency: options.concurrency,
    },
    timestamp: new Date().toISOString(),
    results,
    aggregate: computeAggregate(results),
  };

  writeFileSync(options.outputPath, JSON.stringify(benchmarkResult, null, 2));
  return benchmarkResult;
}

async function runTask(
  task: EvalTask,
  driver: Driver,
  scoringFn: ScoringFn,
  driverOptions: DriverOptions,
): Promise<EvalResult> {
  try {
    const result = await driver.call(task.query, task.context, driverOptions);
    const score = scoringFn(task.expectedAnswer, result.answer);
    const iterations = result.iterations ?? countIterations(result.trace);

    return {
      taskId: task.id,
      query: task.query,
      expectedAnswer: task.expectedAnswer,
      generatedAnswer: result.answer,
      score,
      iterations: iterations || 1,
      wallTimeMs: result.wallTimeMs,
      trace: result.trace,
      ...(result.exitCode !== 0 ? { error: `exit code ${result.exitCode}` } : {}),
    };
  } catch (err) {
    return {
      taskId: task.id,
      query: task.query,
      expectedAnswer: task.expectedAnswer,
      generatedAnswer: "",
      score: 0,
      iterations: 0,
      wallTimeMs: 0,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

export async function runHarness(
  tasks: EvalTask[],
  options: HarnessOptions,
): Promise<BenchmarkResult> {
  const { driver, scoringFn, driverOptions, concurrency, onProgress } = options;

  const existingResults = loadExistingResults(options.outputPath);
  const allResults: EvalResult[] = [];

  // Separate already-completed tasks from pending ones
  const pendingTasks: EvalTask[] = [];
  for (const task of tasks) {
    const existing = existingResults.get(task.id);
    if (existing) {
      allResults.push(existing);
    } else {
      pendingTasks.push(task);
    }
  }

  if (existingResults.size > 0) {
    console.error(
      `Resuming: ${existingResults.size} tasks already completed, ${pendingTasks.length} remaining`,
    );
  }

  const startTime = Date.now();
  let completedCount = allResults.length;
  const totalTasks = tasks.length;

  const processTask = async (task: EvalTask): Promise<void> => {
    const result = await runTask(task, driver, scoringFn, driverOptions);
    allResults.push(result);
    completedCount++;

    // Save incrementally
    saveResults(options, allResults);

    // Report progress
    if (onProgress) {
      const scores = allResults.filter((r) => !r.error).map((r) => r.score);
      const meanScore = scores.length > 0
        ? scores.reduce((a, b) => a + b, 0) / scores.length
        : 0;

      onProgress({
        completed: completedCount,
        total: totalTasks,
        score: result.score,
        meanScore,
        elapsed: formatElapsed(Date.now() - startTime),
      });
    }
  };

  const queue = [...pendingTasks];
  const running = new Set<Promise<void>>();

  while (queue.length > 0 || running.size > 0) {
    // Fill up to concurrency limit
    while (queue.length > 0 && running.size < concurrency) {
      const task = queue.shift()!;
      const promise = processTask(task).then(() => {
        running.delete(promise);
      });
      running.add(promise);
    }

    if (running.size > 0) {
      await Promise.race(running);
    }
  }

  return saveResults(options, allResults);
}
