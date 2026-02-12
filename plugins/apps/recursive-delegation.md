---
name: recursive-delegation
kind: app
version: 0.1.0
description: Depth-aware delegation strategy using recursive rlm calls
tags: [delegation, aggregation, strategy]
---

## Recursive Delegation

You can delegate subtasks to child RLM processes:

    result=$(rlm "classify this question: Is Paris a city?" < /tmp/subset.txt)
    echo "$result"

### When to delegate

- The task requires processing many items individually
- Each item needs independent reasoning (classification, extraction)
- The aggregate result combines the per-item results

### Fan-out pattern

    # Split data into chunks
    split -l 50 $RLM_INPUT /tmp/chunk_

    # Process each chunk
    for chunk in /tmp/chunk_*; do
        result=$(rlm "count items matching criteria X" < "$chunk")
        echo "$result" >> /tmp/results.txt
    done

    # Aggregate
    python3 -c "
    with open('/tmp/results.txt') as f:
        total = sum(int(line.strip()) for line in f if line.strip().isdigit())
    print(total)
    "

### Rules

- Each child rlm call gets its own sandbox and iterations
- Children do NOT have access to your files unless you pipe data to them
- Keep delegation depth shallow — prefer one level of fan-out
- If the task is simple enough to solve with grep/awk/python, don't delegate
