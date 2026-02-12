# unix-rlm/bin

Three executables that implement a Unix-native RLM (Recursive Language Model) -- an LLM agent that solves tasks by writing and executing code in a persistent Linux filesystem, with the ability to delegate subtasks recursively.

## Overview

| File | What it is | Cost |
|------|-----------|------|
| `rlm` | LLM in a REPL loop with a bash sandbox. Iterates, runs code, delegates. | 3-15 API calls |
| `llm` | One-shot LLM call. No loop, no code execution. | 1 API call |
| `_rlm-common.sh` | Shared library sourced by both. Not executable on its own. | -- |

`rlm` is the main agent. It puts an LLM in a loop: the model writes code in ```` ```repl ```` blocks, `rlm` executes each block in bash, feeds the output back, and repeats until the model calls `RETURN "answer"` or exhausts its iteration budget. The filesystem persists across iterations, so the model can build up state incrementally.

`llm` is a lightweight helper for simple subtasks. It makes a single API call and prints the response. No code execution, no iteration. Both `rlm` and `llm` are available inside the sandbox, so the model can call either one to delegate work.

## rlm

```
rlm "query"
echo "data" | rlm "query"
```

The core agent. Each invocation:

1. Gets its own working directory under `/rlm/tree/` (with `trace/` and `children/` subdirs).
2. Enters a loop: build conversation from trace files on disk, call the LLM, extract ```` ```repl ```` blocks, execute them in bash, write outputs to trace, repeat.
3. Terminates when the model calls `RETURN "value"` (success), hits the iteration limit (failure), or produces two consecutive responses with no code blocks (failure).

The answer is printed to stdout. Metadata (iteration count, workdir) goes to stderr.

### Recursion and delegation

`rlm` supports recursive invocation. A parent `rlm` can call `rlm "subtask"` or `llm "question"` from inside its code blocks. Children get their own workdir nested under the parent's, their own iteration budget, and their own conversation history.

The iteration budget decays with depth: root gets `RLM_MAX_ITERATIONS` (default 15), depth 1 gets 7, depth 2 gets 4, depth 3+ gets 3. When `RLM_DEPTH >= RLM_MAX_DEPTH`, `rlm` falls back to a single flat LLM call (no loop, no sandbox) -- behaving like `llm`.

A parent can pass a custom system prompt to a child:

```
RLM_CHILD_SYSTEM_PROMPT="You are an expert at X. Do Y." rlm "subtask"
```

### Key environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENROUTER_API_KEY` | (from `/etc/rlm/api-key`) | API key for OpenRouter |
| `RLM_MODEL` | `anthropic/claude-sonnet-4` | Model identifier |
| `RLM_MAX_ITERATIONS` | `15` | Max iterations for the root invocation |
| `RLM_MAX_DEPTH` | `3` | Max recursion depth (0-indexed) |
| `RLM_MAX_TOKENS` | `16384` | Max tokens per LLM response |
| `RLM_PLUGINS` | (none) | Comma-separated plugin names to load |
| `RLM_PLUGINS_DIR` | `../plugins` | Directory containing plugin `.md` files |

Internal variables set by `rlm` and visible to children: `RLM_WORKDIR`, `RLM_INPUT`, `RLM_DEPTH`, `RLM_ANSWER_FILE`, `RLM_INVOCATION_ID`, `RLM_PARENT_ID`, `RLM_ROOT_QUERY`, `RLM_LINEAGE`, `RLM_EFFECTIVE_MAX_ITERS`.

### Trace directory

Every iteration is recorded in `$RLM_WORKDIR/trace/`:
- `001-response.md` -- the LLM's raw response
- `001-output.txt` -- stdout+stderr from executing the code blocks
- `001-output-truncated.txt` -- shortened version fed back to the LLM (if output exceeded 50KB / 1000 lines)

This enables crash recovery (`_RLM_RESUME_DIR`) and post-hoc debugging.

### Plugins

Plugins are Markdown files in `RLM_PLUGINS_DIR`. They are appended to the system prompt. Load them with:

```
RLM_PLUGINS="verify-before-return,structured-data-aggregation" rlm "query"
```

## llm

```
llm "query"
echo "data" | llm "query"
```

A single LLM call with no loop, no code execution, and no sandbox. The default system prompt tells the model to answer directly and concisely with no explanation or formatting.

Use `llm` instead of `rlm` when the subtask is simple: classifying an item, extracting a value, answering a factual question. It costs exactly 1 API call.

If data is piped in, it is appended to the query as `Context: <data>`.

Override the system prompt with `RLM_LLM_SYSTEM_PROMPT`:

```
RLM_LLM_SYSTEM_PROMPT="You are a sentiment classifier. Reply with: positive, negative, or neutral." \
  echo "I love this product" | llm "Classify the sentiment."
```

## _rlm-common.sh

Shared library sourced by both `rlm` and `llm`. Provides:

- **API key resolution**: checks `OPENROUTER_API_KEY` env var, falls back to `/etc/rlm/api-key`.
- **`call_llm` function**: makes the actual OpenRouter API call. Handles retries (up to 3 attempts) for rate limits (429), HTTP errors, empty responses, and curl failures. Supports a mock mode (`_RLM_MOCK_DIR`) for testing, where responses are read from numbered Markdown files instead of calling the API.

Not meant to be run directly. Has no shebang and no `set -euo pipefail` (the sourcing script provides those).

## Installation

Add the `bin/` directory to your PATH, or symlink `rlm` and `llm` into a directory already on PATH (e.g., `/usr/local/bin`). Both scripts automatically add their own directory to PATH so that recursive `rlm` and `llm` calls work regardless of how the parent was invoked.

Make sure `rlm`, `llm`, and `_rlm-common.sh` are in the same directory. Both `rlm` and `llm` locate `_rlm-common.sh` relative to their own path.

Provide an API key either via the `OPENROUTER_API_KEY` environment variable or by writing it to `/etc/rlm/api-key`.

Dependencies: `bash`, `curl`, `jq`. The sandbox has access to whatever is installed on the host (`python3`, `git`, `apt`, `pip`, etc.).
