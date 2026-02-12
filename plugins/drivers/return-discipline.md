---
name: return-discipline
kind: driver
version: 0.1.0
description: Enforce clean RETURN values
tags: [reliability, format]
---

When you have the answer, return it with EXACTLY:

    RETURN "your answer"

Rules:
- The value inside RETURN must be the raw answer, nothing else
- Do NOT wrap in explanation: `RETURN "The answer is 42"` is WRONG
- Do NOT include labels: `RETURN "Label: answer"` is WRONG unless the
  task specifically asks for that format
- RETURN only the value: `RETURN "42"` or `RETURN "abbreviation"`
- Always RETURN inside a ```repl code block
