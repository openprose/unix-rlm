#!/usr/bin/env bats
# test/extraction.bats — code block extraction tests for rlm

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true

    # Source only the extract_code_blocks function from the rlm script.
    # Use awk to extract the full function body (handles nested braces).
    eval "$(awk '/^extract_code_blocks\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "single repl block extracted" {
    local response='Here is some code:

```repl
echo "hello world"
```

That should work.'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    local files=("$blocks_dir"/*.sh)
    assert [ ${#files[@]} -eq 1 ]

    run cat "$blocks_dir/1.sh"
    assert_output --partial 'echo "hello world"'
}

@test "multiple repl blocks extracted" {
    local response='First block:

```repl
echo "one"
```

Second block:

```repl
echo "two"
```

Third block:

```repl
echo "three"
```

Done.'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    local files=("$blocks_dir"/*.sh)
    assert [ ${#files[@]} -eq 3 ]

    run cat "$blocks_dir/1.sh"
    assert_output --partial 'echo "one"'

    run cat "$blocks_dir/2.sh"
    assert_output --partial 'echo "two"'

    run cat "$blocks_dir/3.sh"
    assert_output --partial 'echo "three"'
}

@test "non-repl blocks ignored" {
    local response='Here is bash:

```bash
echo "bash block"
```

Here is python:

```python
print("python block")
```

Here is json:

```json
{"key": "value"}
```

Here is repl:

```repl
echo "repl block"
```

Done.'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    local files=("$blocks_dir"/*.sh)
    assert [ ${#files[@]} -eq 1 ]

    run cat "$blocks_dir/1.sh"
    assert_output --partial 'echo "repl block"'
    refute_output --partial 'bash block'
    refute_output --partial 'python block'
    refute_output --partial 'key'
}

@test "inline backticks ignored" {
    local response='Use the `echo` command and `cat` to process.

Also try `RETURN "value"` in your code.

```repl
echo "actual block"
```

Thats it.'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    local files=("$blocks_dir"/*.sh)
    assert [ ${#files[@]} -eq 1 ]

    run cat "$blocks_dir/1.sh"
    assert_output --partial 'echo "actual block"'
}

@test "empty repl block" {
    local response='Empty block:

```repl
```

Done.'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    local files=("$blocks_dir"/*.sh)
    assert [ ${#files[@]} -eq 1 ]

    assert_file_exist "$blocks_dir/1.sh"
    run cat "$blocks_dir/1.sh"
    assert_output --partial 'RETURN()'
}

@test "RETURN prepended to each block" {
    local response='```repl
echo "block one"
```

```repl
echo "block two"
```'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    run cat "$blocks_dir/1.sh"
    assert_output --partial 'RETURN()'
    assert_output --partial 'printf '\''%s'\'' "$1" > "$RLM_ANSWER_FILE"'
    assert_output --partial 'echo "block one"'

    run cat "$blocks_dir/2.sh"
    assert_output --partial 'RETURN()'
    assert_output --partial 'echo "block two"'
}

@test "nested backticks handled" {
    local response='```repl
result=$(echo "hello")
name='\''test`s value'\''
echo "backtick: \`done\`"
```'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    local files=("$blocks_dir"/*.sh)
    assert [ ${#files[@]} -eq 1 ]

    run cat "$blocks_dir/1.sh"
    assert_output --partial 'result=$(echo "hello")'
}

@test "no repl blocks produces empty directory" {
    local response='Here is some prose with no code blocks.

Just text. Nothing to extract.

```bash
echo "not repl"
```'

    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    assert [ -d "$blocks_dir" ]
    local files=("$blocks_dir"/*.sh)
    # When glob matches nothing, bash returns the literal pattern
    if [ -e "${files[0]}" ]; then
        fail "expected no .sh files in blocks_dir, but found some"
    fi
}
