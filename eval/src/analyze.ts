#!/usr/bin/env npx tsx
/**
 * Post-hoc analysis of eval results.
 *
 * Reads a result JSON file and computes metrics: iteration stats, wall time,
 * behavioral patterns, score distributions, and context-length analysis.
 *
 * Usage:
 *   npx tsx src/analyze.ts                           # analyze most recent result
 *   npx tsx src/analyze.ts results/specific-file.json # analyze specific file
 */

import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import type { BenchmarkResult, EvalResult } from "./drivers/types.js";
import { sorted, mean, median, percentile, std } from "./stats.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

function analyzeIterations(results: EvalResult[]): void {
  const completed = results.filter((r) => !r.error);
  const iterations = completed.map((r) => r.iterations);

  console.log("=== Iteration Statistics ===");
  console.log(`  Mean:    ${mean(iterations).toFixed(2)}`);
  console.log(`  P20:     ${percentile(iterations, 20).toFixed(2)}`);
  console.log(`  Median:  ${median(iterations).toFixed(2)}`);
  console.log(`  P80:     ${percentile(iterations, 80).toFixed(2)}`);
  console.log(`  Min:     ${Math.min(...iterations)}`);
  console.log(`  Max:     ${Math.max(...iterations)}`);
  console.log("");
}

function analyzeWallTime(results: EvalResult[]): void {
  const completed = results.filter((r) => !r.error);
  const times = completed.map((r) => r.wallTimeMs / 1000); // convert to seconds

  console.log("=== Wall Time (seconds) ===");
  console.log(`  Mean:    ${mean(times).toFixed(2)}s`);
  console.log(`  Median:  ${median(times).toFixed(2)}s`);
  console.log(`  P20:     ${percentile(times, 20).toFixed(2)}s`);
  console.log(`  P80:     ${percentile(times, 80).toFixed(2)}s`);
  console.log(`  Min:     ${Math.min(...times).toFixed(2)}s`);
  console.log(`  Max:     ${Math.max(...times).toFixed(2)}s`);
  console.log(`  Total:   ${times.reduce((a, b) => a + b, 0).toFixed(1)}s`);
  console.log("");
}

function analyzeBehavioralPatterns(results: EvalResult[]): void {
  const completed = results.filter((r) => !r.error);
  const total = completed.length;

  if (total === 0) {
    console.log("=== Behavioral Patterns ===");
    console.log("  No completed tasks to analyze.");
    console.log("");
    return;
  }

  // Eager return: RETURN in first iteration
  const eagerReturns = completed.filter((r) => r.iterations === 1).length;
  const eagerReturnRate = eagerReturns / total;

  // Self-correction: score > 0 with iterations > 1
  const selfCorrections = completed.filter((r) => r.score > 0 && r.iterations > 1).length;
  const selfCorrectionRate = selfCorrections / total;

  // Error rate
  const errored = results.filter((r) => !!r.error).length;
  const errorRate = errored / results.length;

  // Recursive usage: check trace paths for children/ directories
  let recursiveUsage = 0;
  for (const r of completed) {
    if (r.trace) {
      try {
        const childrenDir = join(r.trace, "children");
        if (existsSync(childrenDir)) {
          const children = readdirSync(childrenDir);
          if (children.length > 0) {
            recursiveUsage++;
          }
        }
      } catch {
        // Trace path may not be accessible
      }
    }
  }
  const recursiveRate = recursiveUsage / total;

  console.log("=== Behavioral Patterns ===");
  console.log(`  Eager return rate:    ${(eagerReturnRate * 100).toFixed(1)}% (${eagerReturns}/${total})`);
  console.log(`  Self-correction rate: ${(selfCorrectionRate * 100).toFixed(1)}% (${selfCorrections}/${total})`);
  console.log(`  Recursive usage:      ${(recursiveRate * 100).toFixed(1)}% (${recursiveUsage}/${total})`);
  console.log(`  Error rate:           ${(errorRate * 100).toFixed(1)}% (${errored}/${results.length})`);
  console.log("");
}

function analyzeScoreDistribution(results: EvalResult[]): void {
  const completed = results.filter((r) => !r.error);
  const scores = completed.map((r) => r.score);

  // Bucket scores into bins of 0.1
  const buckets = new Array(11).fill(0); // [0.0, 0.1), [0.1, 0.2), ..., [0.9, 1.0], [1.0]
  for (const score of scores) {
    const bucket = Math.min(Math.floor(score * 10), 10);
    buckets[bucket]++;
  }

  const maxCount = Math.max(...buckets, 1);
  const barWidth = 30;

  console.log("=== Score Distribution ===");
  for (let i = 0; i <= 10; i++) {
    const lo = (i / 10).toFixed(1);
    const hi = i < 10 ? ((i + 1) / 10).toFixed(1) : "1.0";
    const label = i < 10 ? `[${lo}, ${hi})` : `[${lo}]    `;
    const count = buckets[i];
    const bar = "#".repeat(Math.round((count / maxCount) * barWidth));
    console.log(`  ${label} ${bar} ${count}`);
  }
  console.log("");
}

function analyzeSuccessByIterations(results: EvalResult[]): void {
  const completed = results.filter((r) => !r.error);

  // Group by iteration count
  const byIterations = new Map<number, { total: number; success: number }>();
  for (const r of completed) {
    const iters = r.iterations;
    const existing = byIterations.get(iters) ?? { total: 0, success: 0 };
    existing.total++;
    if (r.score > 0) {
      existing.success++;
    }
    byIterations.set(iters, existing);
  }

  console.log("=== Success Rate by Iteration Count ===");
  const iterKeys = sorted([...byIterations.keys()]);
  for (const iters of iterKeys) {
    const data = byIterations.get(iters)!;
    const rate = data.total > 0 ? data.success / data.total : 0;
    console.log(
      `  ${iters} iterations: ${(rate * 100).toFixed(0)}% success (${data.success}/${data.total})`,
    );
  }
  console.log("");
}

function analyzeContextLength(results: EvalResult[]): void {
  // Only applicable for S-NIAH tasks (those with s-niah in the task ID)
  const sniahResults = results.filter((r) => r.taskId.startsWith("s-niah-"));
  if (sniahResults.length === 0) {
    return;
  }

  // Group by context length (extracted from task ID: s-niah-{contextLen}-{index})
  const byLength = new Map<number, { scores: number[]; iterations: number[] }>();
  for (const r of sniahResults) {
    const parts = r.taskId.split("-");
    const contextLen = parseInt(parts[2], 10);
    if (isNaN(contextLen)) continue;

    const existing = byLength.get(contextLen) ?? { scores: [], iterations: [] };
    existing.scores.push(r.score);
    existing.iterations.push(r.iterations);
    byLength.set(contextLen, existing);
  }

  const formatLen = (len: number): string => {
    if (len >= 1024 * 1024) return `${(len / (1024 * 1024)).toFixed(0)}M`;
    if (len >= 1024) return `${(len / 1024).toFixed(0)}K`;
    return String(len);
  };

  console.log("=== Context Length Analysis (S-NIAH) ===");
  const lengths = sorted([...byLength.keys()]);
  for (const len of lengths) {
    const data = byLength.get(len)!;
    const avgScore = mean(data.scores);
    const avgIter = mean(data.iterations);
    console.log(
      `  ${formatLen(len).padStart(5)}: score ${avgScore.toFixed(2)} | iterations ${avgIter.toFixed(1)} | n=${data.scores.length}`,
    );
  }
  console.log("");
}

function findLatestResult(): string | null {
  const resultsDir = resolve(__dirname, "..", "results");
  if (!existsSync(resultsDir)) {
    return null;
  }

  const files = readdirSync(resultsDir)
    .filter((f) => f.endsWith(".json"))
    .sort();

  if (files.length === 0) {
    return null;
  }

  return join(resultsDir, files[files.length - 1]);
}

function main(): void {
  let resultPath = process.argv[2];

  if (!resultPath) {
    const latest = findLatestResult();
    if (!latest) {
      console.error("No result files found. Run an eval first, or specify a path.");
      console.error("Usage: npx tsx src/analyze.ts [results/file.json]");
      process.exit(1);
    }
    resultPath = latest;
    console.error(`Analyzing most recent result: ${resultPath}`);
  }

  resultPath = resolve(process.cwd(), resultPath);

  if (!existsSync(resultPath)) {
    console.error(`File not found: ${resultPath}`);
    process.exit(1);
  }

  let data: BenchmarkResult;
  try {
    data = JSON.parse(readFileSync(resultPath, "utf-8"));
  } catch (err) {
    console.error(`Failed to parse ${resultPath}: ${err}`);
    process.exit(1);
  }

  console.log(`\nAnalysis of: ${resultPath}`);
  console.log(`Benchmark: ${data.benchmark} | Model: ${data.model} | ${data.timestamp}`);
  console.log(
    `Tasks: ${data.aggregate.completedTasks} completed, ${data.aggregate.failedTasks} failed`,
  );
  console.log("");

  analyzeIterations(data.results);
  analyzeWallTime(data.results);
  analyzeBehavioralPatterns(data.results);
  analyzeScoreDistribution(data.results);
  analyzeSuccessByIterations(data.results);
  analyzeContextLength(data.results);

  console.log("=== Summary ===");
  console.log(`  Mean score:     ${data.aggregate.meanScore.toFixed(4)}`);
  console.log(`  Median score:   ${data.aggregate.medianScore.toFixed(4)}`);
}

main();
