# Plugins

Plugins are markdown files that get injected into the system prompt at runtime.
They modify how the LLM behaves inside the RLM without changing the runtime
itself. A plugin cannot inject bash, modify environment variables, or alter
execution -- it can only instruct the LLM on how to use the existing sandbox.

## Categories

Plugins are organized into two directories. The runtime treats them identically;
the distinction is conceptual.

### Drivers (`drivers/`)

Short (5-20 lines) model-reliability patches. Fix _how_ the model behaves
inside the RLM. You typically stack several per run.

| Plugin | Purpose |
|---|---|
| `drivers/bash-execution` | Remind the model that code blocks are bash, not Python. Shows correct patterns for running Python via `python3 -c`, heredoc, or script file. |
| `drivers/one-block-per-iteration` | Enforce one code block per response. Prevents fabricated output between blocks. |
| `drivers/return-discipline` | Enforce clean `RETURN "value"` formatting -- raw answer only, no labels or explanation. |
| `drivers/verify-before-return` | Require that the answer was seen in command output before `RETURN`. Prevents hallucinated returns. |
| `drivers/no-tool-calls` | Suppress hallucinated tool/function call blocks. Useful for models (e.g. Gemini) that generate structured tool invocations despite having none. |

### Apps (`apps/`)

Longer (30-100 lines) task architectures. Define _what_ the RLM does for a
class of problems. You typically use one per run.

| Plugin | Purpose |
|---|---|
| `apps/oolong-aggregation` | Step-by-step protocol for counting/aggregation tasks on large text data: inspect, script, verify, return. |
| `apps/recursive-delegation` | Strategy and patterns for fan-out delegation via recursive `rlm` calls, including chunk splitting and result aggregation. |

## Usage

Plugins are activated via the `RLM_PLUGINS` environment variable (comma-separated)
or configured by the eval harness. Each name is a path relative to the plugins
directory, without the `.md` extension.

```bash
# Single plugin
RLM_PLUGINS=drivers/bash-execution rlm "what kernel version is this?"

# Multiple plugins (comma-separated, no spaces)
RLM_PLUGINS=drivers/bash-execution,drivers/one-block-per-iteration,drivers/return-discipline rlm "count the lines"

# With an app plugin
RLM_PLUGINS=drivers/bash-execution,drivers/return-discipline,apps/oolong-aggregation rlm "how many entries mention cats?" < data.txt

# Custom plugin directory
RLM_PLUGINS_DIR=/path/to/my/plugins RLM_PLUGINS=my-custom-plugin rlm "query"

# No plugins (bare RLM, default)
rlm "what is 2+2?"
```

## How Loading Works

The plugin loader in `bin/rlm` does the following:

1. Splits `RLM_PLUGINS` on commas.
2. For each name, resolves it to `${RLM_PLUGINS_DIR}/${name}.md`. The default
   plugins directory is `plugins/` relative to the `bin/rlm` script.
3. Strips YAML frontmatter (everything between the first pair of `---` lines).
4. Concatenates plugin bodies, separated by `---` dividers.
5. Appends the result to the end of `SYSTEM_PROMPT`.

If a plugin file is not found, a warning is printed to stderr and that plugin is
skipped. Order matters: later plugins appear later in the system prompt, so they
can reinforce or override earlier instructions.

## Writing a New Plugin

A plugin is a `.md` file with YAML frontmatter and a body.

### Format

```markdown
---
name: my-plugin
kind: driver
version: 0.1.0
description: One-line description of what this plugin does
tags: [reliability, gemini]
---

The body is injected verbatim into the system prompt. Write it as
instructions to the LLM.

- Use imperative voice ("Do X", "NEVER do Y")
- Be concise -- every token costs context window space
- Include examples of correct and incorrect patterns when helpful
```

### Frontmatter Fields

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Identifier matching the filename (without `.md`) |
| `kind` | Yes | `driver` or `app` |
| `version` | Yes | Semver string |
| `description` | Yes | One-line summary |
| `tags` | No | List of tags for categorization |

The frontmatter is stripped at load time and never reaches the LLM. It exists
for human documentation and future tooling (e.g., profile auto-detection).

### Guidelines

- **Drivers** should be short and focused on a single behavioral fix. A driver
  can be 3 lines.
- **Apps** should define a step-by-step protocol for a class of tasks. Include
  concrete code examples showing the patterns you want the LLM to follow.
- Plugins cannot touch the sandbox. They instruct the LLM; they do not execute
  code or modify the environment.
- Place drivers in `drivers/` and apps in `apps/`.
- Test by running with `RLM_PLUGINS=<category>/<your-plugin>` and inspecting
  the trace files in the workdir to confirm the model follows the instructions.

## Design Principles

1. **The script is the runtime; plugins are the behavior.** `bin/rlm` stays minimal.
   All task logic lives in plugins.
2. **Plugins are markdown.** Easy to read, easy for an LLM to write, and they diff cleanly in git.
3. **Compose by concatenation.** Loading multiple plugins = concatenating their
   bodies. No dependency resolution.
4. **Plugins don't touch the sandbox.** A plugin can only instruct the LLM on
   how to use the existing sandbox.
5. **Keep it minimal.** No build step, no manifest beyond YAML frontmatter.
