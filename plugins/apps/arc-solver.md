---
name: arc-solver
kind: app
version: 0.1.0
description: Protocol for solving ARC-AGI abstract reasoning tasks via iterative hypothesis testing
tags: [arc, reasoning, grids, pattern-recognition]
---

## ARC Solving Protocol

You are solving an Abstract Reasoning Corpus (ARC) task. The task data is in `$RLM_INPUT` as a JSON string containing `train` (input/output example pairs) and `test` (input-only grids to solve). Each grid is a 2D array of integers 0-9 representing colors.

### 1. Parse and Explore

    python3 << 'PYEOF'
    import json, os

    with open(os.environ["RLM_INPUT"]) as f:
        task = json.load(f)

    train = task["train"]
    test = task["test"]

    print(f"Training examples: {len(train)}")
    for i, ex in enumerate(train):
        inp, out = ex["input"], ex["output"]
        print(f"  Train {i}: {len(inp)}x{len(inp[0])} -> {len(out)}x{len(out[0])}")
    for i, ex in enumerate(test):
        inp = ex["input"]
        print(f"  Test {i}: {len(inp)}x{len(inp[0])}")
    PYEOF

Visualize every training example -- both input and output. Use compact grid display. Note dimensions, colors present, symmetries, and special markers.

    python3 << 'PYEOF'
    import json, os

    with open(os.environ["RLM_INPUT"]) as f:
        task = json.load(f)

    for i, ex in enumerate(task["train"]):
        print(f"\n=== Train {i} ===")
        print("Input:")
        for row in ex["input"]:
            print("".join(str(c) for c in row))
        print("Output:")
        for row in ex["output"]:
            print("".join(str(c) for c in row))

    for i, ex in enumerate(task["test"]):
        print(f"\n=== Test {i} ===")
        print("Input:")
        for row in ex["input"]:
            print("".join(str(c) for c in row))
    PYEOF

### 2. Identify Objects and Structure

For each training example, identify:

- **Objects** -- connected regions of the same color (use flood-fill or label connected components)
- **Bounding boxes** -- min/max row and column for each object or color
- **Spatial relationships** -- relative positions, containment, adjacency
- **Symmetries** -- horizontal, vertical, rotational, or translational

Write a Python script to analyze the structure:

    cat > /tmp/analyze.py << 'PYEOF'
    import json, os
    from collections import defaultdict

    with open(os.environ["RLM_INPUT"]) as f:
        task = json.load(f)

    def color_counts(grid):
        counts = defaultdict(int)
        for row in grid:
            for c in row:
                counts[c] += 1
        return dict(counts)

    def bounding_boxes(grid, ignore=0):
        boxes = {}
        for r, row in enumerate(grid):
            for c, val in enumerate(row):
                if val != ignore:
                    if val not in boxes:
                        boxes[val] = [r, c, r, c]
                    else:
                        b = boxes[val]
                        b[0] = min(b[0], r)
                        b[1] = min(b[1], c)
                        b[2] = max(b[2], r)
                        b[3] = max(b[3], c)
        return boxes

    for i, ex in enumerate(task["train"]):
        print(f"\n--- Train {i} ---")
        print(f"Input colors: {color_counts(ex['input'])}")
        print(f"Output colors: {color_counts(ex['output'])}")
        print(f"Input bboxes: {bounding_boxes(ex['input'])}")
        print(f"Output bboxes: {bounding_boxes(ex['output'])}")
    PYEOF
    python3 /tmp/analyze.py

### 3. Formulate Hypotheses

Based on your analysis, consider these transformation families:

- **Region extraction** -- output is a sub-region of the input (corners, center, marked area)
- **Reflection/rotation** -- output is a transformed version of a region
- **Color mapping** -- systematic color replacement or conditional coloring
- **Object manipulation** -- moving, resizing, compositing objects
- **Pattern completion** -- filling in missing parts using symmetry or repetition
- **Overlay/masking** -- a marker (e.g., color 8) covers a region; reconstruct what's underneath

Prioritize simpler rules. Avoid arbitrary constants tuned to specific examples.

### 4. Test Systematically

Write a `transform` function and test it against ALL training examples:

    cat > /tmp/solve.py << 'PYEOF'
    import json, os

    with open(os.environ["RLM_INPUT"]) as f:
        task = json.load(f)

    def transform(grid):
        # ... your transformation logic here ...
        pass

    correct = 0
    for i, ex in enumerate(task["train"]):
        predicted = transform(ex["input"])
        expected = ex["output"]
        match = predicted == expected
        print(f"Train {i}: {'PASS' if match else 'FAIL'}")
        if not match:
            print(f"  Expected: {expected[0] if expected else '[]'}")
            print(f"  Got:      {predicted[0] if predicted else '[]'}")
        if match:
            correct += 1
    print(f"Score: {correct}/{len(task['train'])}")
    PYEOF
    python3 /tmp/solve.py

**Critical:** Always test against ALL training examples before moving on. If any fail, inspect the diff to understand why and refine the hypothesis.

### 5. Generalization Check

Before applying to test inputs, verify your transform generalizes:

- Does it rely on hard-coded dimensions or positions from training data?
- Does it handle different grid sizes?
- Does it handle different orientations or directions?
- Look at the test input -- does it have the same structural features your transform expects?

### 6. Solve and Return

Once your transform passes ALL training examples, apply it and RETURN the result:

    cat > /tmp/final.py << 'PYEOF'
    import json, os

    with open(os.environ["RLM_INPUT"]) as f:
        task = json.load(f)

    def transform(grid):
        # ... your verified transformation logic ...
        pass

    test = task["test"]
    if len(test) == 1:
        result = transform(test[0]["input"])
    else:
        result = [transform(t["input"]) for t in test]
    print(json.dumps(result))
    PYEOF
    python3 /tmp/final.py

Then RETURN the JSON output from the script above.

### What NOT to do

- **Do not skip verification** -- never apply a transform to test without passing all training examples first
- **Do not thrash between unrelated hypotheses** -- when a hypothesis partially works, investigate WHY it fails on specific examples rather than abandoning it entirely
- **Do not forget to RETURN** -- logging a result is not submitting it; you MUST RETURN the JSON grid
- **Do not tune constants to training data** -- if your transform uses magic numbers derived from one example, it won't generalize
- **Do not give up without submitting** -- if you can't find a perfect solution, submit your best attempt; a partially correct answer is better than no answer
- **Do not write raw Python in code blocks** -- always use `python3 << 'PYEOF'` or `python3 /tmp/script.py`; code blocks execute in bash
