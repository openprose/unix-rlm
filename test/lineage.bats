#!/usr/bin/env bats
# test/lineage.bats — Lineage and orientation tests

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true
    unset RLM_INVOCATION_ID RLM_PARENT_ID RLM_ROOT_QUERY RLM_LINEAGE 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "Lineage: root invocation gets RLM_INVOCATION_ID=root" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_INVOCATION_ID"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "root"
}

@test "Lineage: root invocation sets RLM_ROOT_QUERY" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_ROOT_QUERY"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    run "$RLM_BIN" "my test query here" < /dev/null
    assert_success
    assert_output "my test query here"
}

@test "Lineage: child invocation gets depth-based invocation ID" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_INVOCATION_ID"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_DEPTH=1  # Simulating a child
    run "$RLM_BIN" "child query" < /dev/null
    assert_success
    # Should be "d1-c{PID}" — we just check the prefix
    assert_output --regexp "^d1-c[0-9]+$"
}

@test "Lineage: root has empty RLM_PARENT_ID" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "parent=${RLM_PARENT_ID:-EMPTY}"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "parent=EMPTY"
}

@test "Lineage: child inherits RLM_PARENT_ID" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_PARENT_ID"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_DEPTH=1
    export RLM_PARENT_ID="root"
    run "$RLM_BIN" "child query" < /dev/null
    assert_success
    assert_output "root"
}

@test "Lineage: RLM_EFFECTIVE_MAX_ITERS is set for root" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_EFFECTIVE_MAX_ITERS"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=15
    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    # Root (depth 0) gets full budget
    assert_output "15"
}
