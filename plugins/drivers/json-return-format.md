---
name: json-return-format
kind: driver
version: 0.1.0
description: RETURN json.dumps(value) for structured data — prevents serialization bugs
author: sl
tags: [format, reliability, arc]
requires: []
---

## Stringify Structured Returns

When returning structured data (arrays, grids, objects):

**Always** use `RETURN "$(python3 -c "import json; print(json.dumps(value))")"` or pipe through `jq`, never return a raw variable or print statement output.

Returning unquoted or improperly serialized data can cause the harness to receive mangled strings instead of valid JSON. `json.dumps` or `jq` guarantees a clean round-trip.

### Pattern

```bash
# Good: explicit JSON serialization
python3 << 'PYEOF'
import json
result = transform(test_input)
print(json.dumps(result))
PYEOF

# Then capture and return
RETURN "$(python3 /tmp/final.py)"
```

### What this prevents

- Returning Python repr output (`[[1, 2], [3, 4]]` with spaces) instead of JSON (`[[1,2],[3,4]]`)
- Shell interpolation mangling nested brackets or quotes
- Truncated output from large grids not being properly captured
