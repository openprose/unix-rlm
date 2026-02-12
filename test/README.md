# Unit Tests

BATS tests for `rlm`. All tests use mock LLM responses (no API key needed).

## Prerequisites

`bats` plus vendored libs in `test/lib/` (bats-support, bats-assert, bats-file).

## Run

    bats test/

## Test Files

- `return.bats` -- RETURN mechanism and answer output
- `loop.bats` -- multi-turn loop, error recovery, max iterations
- `workdir.bats` -- directory structure and trace files
- `messages.bats` -- conversation history construction
- `extraction.bats` -- code block extraction from responses
- `output.bats` -- stdout/stderr capture and truncation
- `recursion.bats` -- depth tracking and recursive invocations
- `stdin.bats` -- piped input handling
- `parallel.bats` -- concurrent rlm processes
- `crash.bats` -- crash resilience and resume
- `plugins.bats` -- plugin loading into system prompt
- `budget.bats` -- depth-based iteration budget decay
- `lineage.bats` -- invocation IDs and orientation
