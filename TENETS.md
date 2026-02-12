# Tenets

What unix-rlm believes.

## The RLM is an Intelligent Computer

unix-rlm is a self-contained computer whose core is the RLM: a while loop, a model, and a sandbox. The model lives inside the environment. It executes code, observes results, calls itself recursively, and subdivides work across invocations. This is not a chatbot with tools bolted on. It is a general-purpose computer that runs programs.

## Trust the Model

Push complexity into the model, not the engine. The models are getting better. Every guardrail you hardcode in the runtime is a bet against that trajectory. The engine stays minimal; the model handles ambiguity, error recovery, planning, and judgment. When in doubt, let the model figure it out.

## The Sandbox IS the Tool

There is no tool use. There is no function calling. The model gets a real Linux environment -- bash, the filesystem, the full Unix toolchain -- and that is the only interface it needs. `repl` code blocks in, stdout out, loop. Anything the OS can do, the RLM can do.

## Filesystem as Truth

There is no in-memory state. The filesystem is the heap. Trace files are the debug log. The working directory is the conversation. If it is not on disk, it does not exist. This makes the system inspectable, reproducible, and impossible to lie about.

## Irreducible Core

The engine is a single script. No frameworks. No external dependencies beyond bash, jq, and curl. No abstractions that do not pay for themselves. The Zig rewrite targets a single static binary. The artifact is the product.

## Plugins are Programs Written in Prose

Drivers and apps are markdown files -- strings -- injected into the system prompt. Drivers are composable behavioral shims (stack many). Apps are task architectures (run one). Complex control flow, state management, and composition are all expressed in natural language, and the RLM self-configures into the structures these programs describe. This is what makes the system programmable without making the engine complex.

## Explicit Termination

The loop runs until the model calls `RETURN`. There is no implicit termination. There is no timeout-as-success. The model must decide it is done and say so. This is a hard contract.

## Fail Loudly

Errors are surfaced, not swallowed. If the model's code fails, the error goes back into the context and the model sees it. No cleanup on exit -- trace files persist as the forensic record. Silent failure is the only unacceptable failure.

## Cost-Aware Delegation

`llm` is a single-shot call. `rlm` is a recursive loop. They have different cost profiles and the model should know the difference. Use the cheap thing when the cheap thing works. Recurse when the problem demands it.

## Testable Through Seams

Testability comes from environment variables and filesystem conventions, not mocks or dependency injection frameworks. Swap the model endpoint, override the plugins directory, set the max iterations to 1 -- the seams are already there because the design is honest about its boundaries.

## One Command, Sixty Seconds

A stranger installs unix-rlm, sets an API key, and runs a query. That is the entire onboarding. If it takes longer than sixty seconds or requires reading a guide, something is wrong.

## Standalone

unix-rlm is a public, open-source tool that stands on its own. No proprietary cloud service is required. No sister repo is assumed. A user should be able to discover, install, and use unix-rlm without ever knowing anything else exists.

## Bash Proved It, Zig Ships It

The bash implementation is the proof of concept that validated every idea in this list. The Zig implementation is the real product: a single static binary, no runtime dependencies, deployable anywhere. The concept does not change. The artifact gets serious.
