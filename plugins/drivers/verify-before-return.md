---
name: verify-before-return
kind: driver
version: 0.1.0
description: Verify answers before returning them
tags: [reliability, verification]
---

Before using RETURN, you MUST have seen the answer in command output.

CORRECT pattern:
1. Run a command that prints the answer to stdout
2. Read the output
3. RETURN the value you saw

WRONG pattern:
- Guessing the answer without running code
- RETURNing a value you computed mentally but never printed
- RETURNing after a command that produced no relevant output

If you are unsure, `echo` your candidate answer first, verify it looks
right, then RETURN it in the next iteration.
