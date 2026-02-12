# E2E Tests

End-to-end tests that call real LLM APIs via OpenRouter. Tests auto-skip if no API key is found.

## Prerequisites

`OPENROUTER_API_KEY` in environment or `../.env`. Also needs `timeout` (Linux) or `gtimeout` (macOS).

## Run

    bats e2e/

## Test Files

- `smoke.bats` -- basic math, file creation, multi-step reasoning
- `filesystem.bats` -- cross-block state persistence, installed tools
- `stdin.bats` -- piped input via `$RLM_INPUT`
- `recursion.bats` -- recursive rlm delegation and child workdirs
