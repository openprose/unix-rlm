#!/usr/bin/env npx tsx
/**
 * CLI entry point for the eval harness.
 *
 * Usage:
 *   npx tsx src/run.ts --benchmark s-niah --model anthropic/claude-sonnet-4
 *   npx tsx src/run.ts --benchmark oolong --model anthropic/claude-sonnet-4 --max-tasks 10
 *   npx tsx src/run.ts --benchmark s-niah --driver ssh --host user@box --model anthropic/claude-sonnet-4
 */

import minimist from "minimist";
import { mkdirSync, existsSync } from "node:fs";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { generateSNIAHTasks } from "./datasets/s-niah.js";
import { loadOolongTasks } from "./datasets/oolong.js";
import { LocalDriver } from "./drivers/local.js";
import { SshDriver } from "./drivers/ssh.js";
import { runHarness } from "./harness.js";
import { exactMatch, oolongScore } from "./scoring.js";
import type { Driver } from "./drivers/types.js";
import type { EvalTask } from "./datasets/s-niah.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const USAGE = `
Unix RLM Eval Harness

Usage:
  npx tsx src/run.ts --benchmark <benchmark> --model <model> [options]

Required:
  --benchmark       Benchmark to run: "s-niah" or "oolong"
  --model           OpenRouter model identifier (e.g. "anthropic/claude-sonnet-4")

Options:
  --driver          Driver: "local" (default), "ssh", or path to custom driver
  --host            SSH host (required when --driver ssh)
  --concurrency     Parallel tasks (default: 5)
  --max-iterations  Max RLM loop iterations (default: 15)
  --max-depth       Max recursion depth (default: 2)
  --max-tasks       Limit number of tasks (default: all)
  --tasks-per-length S-NIAH: tasks per context length (default: 8)
  --context-len     OOLONG: context length filter (default: 131072)
  --dataset-filter  OOLONG: dataset filter (default: trec_coarse)
  --output          Output file path (default: auto-generated)
  --help            Show this help message
`.trim();

function printUsage(): void {
  console.log(USAGE);
}

function formatModelForFilename(model: string): string {
  return model.replace(/\//g, "_").replace(/[^a-zA-Z0-9_-]/g, "");
}

function formatTimestamp(): string {
  return new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19) + "Z";
}

async function main(): Promise<void> {
  const args = minimist(process.argv.slice(2), {
    string: ["benchmark", "model", "driver", "host", "output", "dataset-filter"],
    default: {
      driver: "local",
      concurrency: 5,
      "max-iterations": 15,
      "max-depth": 2,
      "tasks-per-length": 8,
      "context-len": 131072,
      "dataset-filter": "trec_coarse",
    },
    alias: {
      h: "help",
    },
  });

  if (args.help) {
    printUsage();
    process.exit(0);
  }

  if (!args.benchmark) {
    console.error("Error: --benchmark is required (s-niah or oolong)");
    printUsage();
    process.exit(1);
  }

  if (!args.model) {
    console.error("Error: --model is required");
    printUsage();
    process.exit(1);
  }

  const benchmark = args.benchmark;
  const model = args.model;
  const driverName = args.driver;
  const host = args.host;
  const concurrency = Number(args.concurrency);
  const maxIterations = Number(args["max-iterations"]);
  const maxDepth = Number(args["max-depth"]);
  const maxTasks = args["max-tasks"] ? Number(args["max-tasks"]) : undefined;
  const tasksPerLength = Number(args["tasks-per-length"]);
  const contextLen = Number(args["context-len"]);
  const datasetFilter = args["dataset-filter"];

  if (benchmark !== "s-niah" && benchmark !== "oolong") {
    console.error(`Error: unknown benchmark "${benchmark}". Use "s-niah" or "oolong".`);
    process.exit(1);
  }

  let driver: Driver;
  if (driverName === "local") {
    driver = new LocalDriver({ model });
  } else if (driverName === "ssh") {
    if (!host) {
      console.error("Error: --host is required when using --driver ssh");
      process.exit(1);
    }
    driver = new SshDriver(host, { model });
  } else {
    // Custom driver: try to load from path
    try {
      const driverPath = resolve(process.cwd(), driverName);
      const mod = await import(driverPath);
      if (!mod.default && !mod.createDriver) {
        console.error(
          `Error: custom driver at ${driverName} must export a default Driver or createDriver function`,
        );
        process.exit(1);
      }
      driver = mod.default ?? mod.createDriver();
    } catch (err) {
      console.error(`Error loading custom driver "${driverName}": ${err}`);
      process.exit(1);
    }
  }

  let tasks: EvalTask[];
  let scoringFn: (expected: string, actual: string) => number;

  if (benchmark === "s-niah") {
    console.error(`Generating S-NIAH tasks (${tasksPerLength} per context length)...`);
    tasks = generateSNIAHTasks({ tasksPerLength });
    scoringFn = exactMatch;
  } else {
    console.error(`Loading OOLONG tasks (filter: ${datasetFilter}, context-len: ${contextLen})...`);
    tasks = await loadOolongTasks({
      datasetFilter,
      contextLength: contextLen,
    });
    scoringFn = oolongScore;
  }

  if (maxTasks !== undefined && maxTasks < tasks.length) {
    tasks = tasks.slice(0, maxTasks);
  }

  console.error(`Loaded ${tasks.length} tasks`);

  const resultsDir = resolve(__dirname, "..", "results");
  if (!existsSync(resultsDir)) {
    mkdirSync(resultsDir, { recursive: true });
  }

  const outputPath =
    args.output ??
    join(resultsDir, `${benchmark}_${formatModelForFilename(model)}_${formatTimestamp()}.json`);

  console.error(`Output: ${outputPath}`);
  console.error(`Driver: ${driverName}, Concurrency: ${concurrency}`);
  console.error(`Max iterations: ${maxIterations}, Max depth: ${maxDepth}`);
  console.error("");

  const result = await runHarness(tasks, {
    driver,
    scoringFn,
    driverOptions: {
      maxIterations,
      maxDepth,
    },
    concurrency,
    outputPath,
    benchmark,
    model,
    driverName,
    onProgress: (progress) => {
      process.stderr.write(
        `\r[${progress.completed}/${progress.total}] score: ${progress.score.toFixed(2)} | mean: ${progress.meanScore.toFixed(2)} | elapsed: ${progress.elapsed}`,
      );
    },
  });

  process.stderr.write("\n\n");

  const agg = result.aggregate;
  console.log("=== Eval Summary ===");
  console.log(`Benchmark:    ${benchmark}`);
  console.log(`Model:        ${model}`);
  console.log(`Tasks:        ${agg.completedTasks} completed, ${agg.failedTasks} failed`);
  console.log("");
  console.log(`Mean score:   ${agg.meanScore.toFixed(4)}`);
  console.log(`Median score: ${agg.medianScore.toFixed(4)}`);
  console.log(`Std score:    ${agg.stdScore.toFixed(4)}`);
  console.log(`P25 score:    ${agg.p25Score.toFixed(4)}`);
  console.log(`P75 score:    ${agg.p75Score.toFixed(4)}`);
  console.log("");
  console.log(`Mean iterations:  ${agg.meanIterations.toFixed(1)}`);
  console.log(`Mean wall time:   ${(agg.meanWallTimeMs / 1000).toFixed(1)}s`);
  console.log(`Total wall time:  ${(agg.totalWallTimeMs / 1000).toFixed(1)}s`);
  console.log("");
  console.log(`Results saved to: ${outputPath}`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
