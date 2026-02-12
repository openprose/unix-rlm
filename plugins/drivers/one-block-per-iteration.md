---
name: one-block-per-iteration
kind: driver
version: 0.1.0
description: Enforce one code block per response
tags: [reliability]
---

Write exactly ONE code block per response. After the block executes, you will
see the real output and can write your next block.

NEVER write multiple code blocks in one response. NEVER fabricate or imagine
output between blocks. Variables don't persist between blocks -- use files to pass data.
