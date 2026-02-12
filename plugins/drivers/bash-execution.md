---
name: bash-execution
kind: driver
version: 0.1.0
description: Clarify that code blocks execute in bash, not Python
tags: [reliability, execution]
---

Code blocks run in **bash**, not Python. Do NOT write raw Python code
in your code blocks.

To run Python, use one of these patterns:

    python3 -c 'print("hello")'

    python3 << 'PYEOF'
    import json
    data = json.load(open("/path/to/file"))
    print(len(data))
    PYEOF

    cat > /tmp/script.py << 'PYEOF'
    import sys
    # multi-line script here
    PYEOF
    python3 /tmp/script.py

NEVER write `import`, `def`, `for x in range(...)`, or other Python syntax
directly in a code block. It will fail with "command not found".
