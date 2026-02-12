---
name: oolong-aggregation
kind: app
version: 0.1.0
description: Protocol for counting/aggregation tasks on large text data
tags: [aggregation, oolong, data]
---

## Aggregation Protocol

The input data is at the file path `$RLM_INPUT`. It is plain text, NOT JSON.

### Step 1: Inspect the data format

    head -20 $RLM_INPUT
    wc -l $RLM_INPUT

Do not skip this step.

### Step 2: Write a processing script to a file

For complex data processing, write a Python script to a file first:

    cat > /tmp/process.py << 'PYEOF'
    import os

    input_file = os.environ["RLM_INPUT"]
    with open(input_file) as f:
        data = f.read()

    # Parse and process the data
    lines = data.strip().split("\n")
    print(f"Total lines: {len(lines)}")
    # ... your processing logic ...
    PYEOF
    python3 /tmp/process.py

### Step 3: Verify the result

Print the answer to stdout and sanity-check it.

### Step 4: RETURN

Then RETURN the raw answer.

### Rules

- NEVER guess counts or frequencies — always compute them with code
- NEVER count by reading text visually — use `grep -c`, `wc -l`, or Python
- If the data is too large to process at once, use `grep`, `awk`, or `sort |
  uniq -c` to aggregate
- Always inspect before processing — do not assume the format
