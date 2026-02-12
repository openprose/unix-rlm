# Unix RLM

An RLM (Recursive Language Model) whose sandbox is a full Linux filesystem. Bash is the shell. The whole computer is the environment. `rlm` is a single bash script that implements the RLM loop: an LLM generates code, the code executes in a persistent Linux environment, and the output feeds back to the LLM until it calls `RETURN` with an answer.

## Quick Start

```bash
curl -sSL https://raw.githubusercontent.com/openprose/unix-rlm/main/install.sh | bash
export OPENROUTER_API_KEY="sk-or-v1-..."
rlm "What is the sum of the first 100 prime numbers?"
```

## How It Works

`rlm` runs a loop. It sends your query to an LLM, which responds with code in `` ```repl `` fenced blocks. `rlm` executes that code in the real Linux environment and captures the output. If the code called `RETURN "value"`, `rlm` prints the value to stdout and exits. Otherwise, the output is fed back to the LLM as context, and the loop continues. The LLM can self-correct errors, inspect files, install packages, and call `rlm` recursively.

Every invocation writes trace files to `/rlm/tree/{PID}/trace/` -- the full conversation (LLM responses and execution outputs) is on disk. This is the debug log.

```
query --> LLM --> extract ```repl blocks --> execute --> check RETURN
  ^                                                         |
  |                                                         v
  +------------ feed output back ---------- no RETURN? ----+
```

## Usage

```bash
# Ask a question
rlm "What is the sum of the first 100 prime numbers?"

# Pipe data as context -- saved to $RLM_INPUT for programmatic access
cat large-dataset.csv | rlm "How many rows have a value greater than 1000?"

# Capture the answer
result=$(rlm "What is today's date in ISO format?")

# Recursion -- rlm can call itself from within code blocks
rlm "Summarize each section of this 500-page document" < book.txt
```

The LLM has full access to the Linux environment: bash, python3, jq, curl, git, and every standard Unix tool. It can install more at runtime with `apt` or `pip`. Files persist across code blocks. The filesystem is the heap.

## Configuration

All configuration is via environment variables. The LLM never sees these.

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENROUTER_API_KEY` | (read from `/etc/rlm/api-key` if unset) | OpenRouter API key |
| `RLM_MODEL` | `anthropic/claude-sonnet-4` | OpenRouter model identifier |
| `RLM_MAX_ITERATIONS` | `15` | Max loop iterations per invocation |
| `RLM_MAX_DEPTH` | `3` | Max recursion depth |
| `RLM_MAX_TOKENS` | `16384` | Max tokens per LLM response |

## Installation

### curl-to-bash

```bash
curl -sSL https://raw.githubusercontent.com/openprose/unix-rlm/main/install.sh | bash
```

Installs `rlm` to `/usr/local/bin/rlm`. Use `PREFIX` for a custom location:

```bash
PREFIX=$HOME/.local curl -sSL https://raw.githubusercontent.com/openprose/unix-rlm/main/install.sh | bash
```

### Docker

```bash
docker build -t rlm .
docker run -e OPENROUTER_API_KEY="sk-or-v1-..." rlm "What is 2 + 2?"
```

The image includes bash, jq, curl, python3, and git.

### From source

```bash
git clone https://github.com/openprose/unix-rlm.git
cd unix-rlm
./bin/rlm "Hello, world"
```

Or install system-wide:

```bash
./install.sh
```

## Requirements

**Required:** bash (4+), jq, curl

**Optional:** python3, git (included in the Docker image)

**API key:** An [OpenRouter](https://openrouter.ai/) API key. Set `OPENROUTER_API_KEY` or write it to `/etc/rlm/api-key`.

## Running Tests

Unit tests use a mock LLM (no API key needed). E2E tests make real API calls.

```bash
# Unit tests -- 67 tests, all mocked
bats test/

# E2E tests -- 9 tests, requires OPENROUTER_API_KEY
bats e2e/

# Specific test file
bats test/loop.bats
```

Test dependencies: [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System). The BATS helper libraries (bats-support, bats-assert, bats-file) are vendored in `test/lib/`.

## Project Structure

```
unix-rlm/
  bin/rlm               # the script -- self-contained
  test/                  # BATS unit tests (67 tests, mock LLM)
    test_helper.bash
    *.bats
    fixtures/            # mock LLM response fixtures
    lib/                 # vendored BATS libraries
  e2e/                   # BATS E2E tests (9 tests, real LLM)
    e2e_helper.bash
    *.bats
  eval/                  # TypeScript eval harness
    src/
      run.ts             # CLI entry point
      harness.ts         # concurrent task runner
      scoring.ts         # scoring functions
      analyze.ts         # post-hoc analysis
      drivers/           # local, ssh, custom drivers
      datasets/          # s-niah, oolong loaders
  install.sh             # curl-to-bash installer
  Dockerfile             # minimal Docker image
  LICENSE                # MIT
  README.md
```

## Eval

The eval harness measures `rlm`'s performance on real tasks. It runs benchmarks, scores results, and produces metrics reports.

### Running an eval

```bash
cd eval && npm install

# S-NIAH: needle-in-haystack across context lengths (8K-256K chars)
npx tsx src/run.ts --benchmark s-niah --model anthropic/claude-sonnet-4

# OOLONG: long-context aggregation tasks
npx tsx src/run.ts --benchmark oolong --model anthropic/claude-sonnet-4

# With options
npx tsx src/run.ts --benchmark s-niah --model anthropic/claude-sonnet-4 \
  --concurrency 10 --max-tasks 20 --max-iterations 15

# Via SSH on a remote host
npx tsx src/run.ts --benchmark s-niah --model anthropic/claude-sonnet-4 \
  --driver ssh --host user@box
```

### Benchmarks

- **S-NIAH** (Single Needle in a Haystack) -- tests whether `rlm` can find specific information in long piped contexts. Synthetically generated, no downloads.
- **OOLONG** (Long-Context Aggregation) -- tests whether `rlm` can aggregate information across contexts that exceed the LLM's context window. Downloaded from HuggingFace.

### Analyzing results

```bash
npx tsx src/analyze.ts                           # most recent result
npx tsx src/analyze.ts results/specific-file.json # specific file
```

Produces iteration statistics, wall time analysis, behavioral patterns (eager return rate, self-correction rate, recursive usage), score distributions, and context-length breakdowns.

See [EVAL_PLAN.md](../EVAL_PLAN.md) for full details.

## Security

`rlm` executes LLM-generated code with the same privileges as the calling user. When deployed on a managed VM (e.g., a Firecracker microVM), the VM is the security boundary. On other platforms, the operator is responsible for isolation (container, VM, etc.). Do not run `rlm` with elevated privileges on a shared system without appropriate sandboxing.

The API key is read from `OPENROUTER_API_KEY` or `/etc/rlm/api-key` at startup. It is sent only to the OpenRouter API endpoint.

## License

MIT. See [LICENSE](LICENSE).

## Further Reading

See [SPEC.md](../SPEC.md) for the full v1 specification.
