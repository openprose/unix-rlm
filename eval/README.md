# Unix RLM Eval Harness

Benchmarks for measuring RLM performance on real tasks with real LLM calls. Not tests (pass/fail) — evals produce scores, metrics, and behavioral analysis.

## Architecture

```
eval/
	package.json
	tsconfig.json
	src/
		run.ts                  # CLI entry point
		harness.ts              # concurrent task runner with resumability
		scoring.ts              # exactMatch, oolongScore, f1Score
		analyze.ts              # post-hoc trace analysis
		drivers/
			types.ts              # Driver interface and result types
			local.ts              # subprocess driver (default)
			ssh.ts                # SSH remote driver
		datasets/
			s-niah.ts             # synthetic needle-in-haystack generator
			oolong.ts             # long-context aggregation loader
	data/                     # benchmark data downloads (gitignored)
	results/                  # eval output JSON (gitignored)
```

## Drivers

The eval harness invokes the `rlm` bash script via a `Driver` interface. Built-in drivers:

- **local** (default): Spawns `rlm` as a subprocess on the local machine
- **ssh**: Runs `rlm` via SSH on a remote host

External drivers (not shipped with unix-rlm) can be loaded via `--driver path/to/driver.ts`.

## Benchmarks

### S-NIAH (Single Needle in a Haystack)

**What it tests:** Can the RLM find specific information in long contexts by piping input and processing it programmatically?

**Source:** Synthetically generated (no download)

**Task structure:**
- A "needle" (random fact like `"The secret code for Project Alpha523 is: crimson-falcon-4271"`) is embedded in filler text
- Context lengths: 8K, 16K, 32K, 64K, 128K, 256K characters
- Default: 8 tasks per context length (48 total)
- Question: "What is the secret code for Project Alpha523?"
- Answer: "crimson-falcon-4271"

**Scoring:** `exactMatch` — case-insensitive exact match after trimming. Returns 0 or 1.

### OOLONG (Long-Context Aggregation)

**What it tests:** Can the RLM aggregate information across a long context that exceeds the LLM's context window?

**Source:** HuggingFace `oolongbench/oolong-synth`. Downloaded to `eval/data/oolong/`

**Task structure:**
- Long contexts (~128K tokens) containing structured data
- Questions like "What is the least common label?" or "How many items have label X?"
- Default: 50 tasks, `trec_coarse` dataset
- Answers are strings or numbers

**Scoring:** `oolongScore` — exponential decay for numeric answers (`0.75^|difference|`), case-insensitive substring matching for comparison phrases, exact match for other text. Range: [0, 1].

## Harness Features

**Concurrency:** Run N tasks in parallel (default: 5). Each `rlm` invocation is an independent process.

**Resumability:** Results are saved incrementally to JSON. Re-running with the same output file skips completed tasks.

**Progress Reporting:** Real-time status: `[12/50] score: 0.85 | mean: 0.72 | elapsed: 3m42s`

**Result Structure:** Full `BenchmarkResult` with per-task details, aggregate statistics, and trace paths for post-hoc analysis.

## Usage

### Running Evals

```bash
# Run S-NIAH (local, default driver)
npx tsx src/run.ts --benchmark s-niah --model anthropic/claude-sonnet-4-5-20250929

# Run OOLONG
npx tsx src/run.ts --benchmark oolong --model anthropic/claude-sonnet-4-5-20250929

# Via SSH on a remote Linux box
npx tsx src/run.ts \
	--benchmark s-niah \
	--model anthropic/claude-sonnet-4-5-20250929 \
	--driver ssh --host user@box

# With options
npx tsx src/run.ts \
	--benchmark s-niah \
	--model anthropic/claude-sonnet-4-5-20250929 \
	--concurrency 10 \
	--max-iterations 15 \
	--max-depth 2 \
	--max-tasks 20
```

### CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--benchmark` | (required) | `s-niah` or `oolong` |
| `--model` | (required) | OpenRouter model identifier |
| `--driver` | `local` | `local`, `ssh`, or path to custom driver module |
| `--host` | | SSH host (required when `--driver ssh`) |
| `--concurrency` | `5` | Parallel tasks |
| `--max-iterations` | `15` | Max RLM loop iterations |
| `--max-depth` | `2` | Max recursion depth |
| `--max-tasks` | all | Limit number of tasks |
| `--tasks-per-length` | `8` | S-NIAH: tasks per context length |
| `--context-len` | `131072` | OOLONG: context length filter |
| `--dataset-filter` | `trec_coarse` | OOLONG: dataset filter |
| `--output` | auto-generated | Output file path |

### Analyzing Results

```bash
# Analyze most recent result
npx tsx src/analyze.ts

# Analyze specific file
npx tsx src/analyze.ts results/specific-file.json
```

The analyzer computes:
- Iteration statistics (mean, median, P20, P80, min, max)
- Wall time per task
- Behavioral patterns (eager return rate, self-correction rate, recursive usage, error rate)
- Score distribution histogram
- Success rate by iteration count
- Context length analysis (S-NIAH only)

## Results

Output files: `eval/results/{benchmark}_{model}_{timestamp}.json`

Contains full `BenchmarkResult` with:
- Per-task results (query, expected/generated answers, score, iterations, wall time, trace path)
- Aggregate statistics (mean/median/std/p25/p75 scores, iteration stats, wall time, task counts)
- Config metadata (driver, maxIterations, maxDepth, concurrency)

## Scoring Functions

**exactMatch(expected, actual):** Case-insensitive exact match after trimming. Returns 0 or 1.

**oolongScore(expected, actual):** Exponential decay for numeric answers (`0.75^|difference|`), substring matching for comparison phrases, exact match for text. Returns [0, 1].

**f1Score(expected, actual):** Token-level F1 score. Tokenizes by splitting on whitespace and punctuation, computes precision and recall. Returns [0, 1].

## Setup

```bash
cd eval
npm install
```

For OOLONG benchmarks, ensure data files are in `eval/data/oolong/` (downloaded from HuggingFace `oolongbench/oolong-synth`).
