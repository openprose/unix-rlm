#!/usr/bin/env bats
# test/recursion.bats — Recursion tests

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "Depth starts at 0: RLM_DEPTH is 0 for root invocation" {
    # Use a mock that echoes RLM_DEPTH then RETURNs it
    local mock_dir
    mock_dir=$(mock_responses '```repl
echo "depth=$RLM_DEPTH"
RETURN "$RLM_DEPTH"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    run "$RLM_BIN" "test depth" < /dev/null
    assert_success
    # The depth INSIDE the loop is 1 (incremented before workdir setup/loop)
    # because export RLM_DEPTH=$((RLM_DEPTH + 1)) runs before the loop.
    # The child code block sees RLM_DEPTH=1.
    assert_output "1"
}

@test "Depth increments for children: child sees RLM_DEPTH=1" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_DEPTH"
```')

    export _RLM_MOCK_DIR="$mock_dir"

    # Parent (depth=0) sees depth=1 inside its loop
    run "$RLM_BIN" "test depth" < /dev/null
    assert_success
    assert_output "1"

    # Child (depth=1) sees depth=2 inside its loop
    export RLM_DEPTH=1
    rm -rf "$_RLM_TREE_ROOT"
    mkdir -p "$_RLM_TREE_ROOT"
    run "$RLM_BIN" "test depth" < /dev/null
    assert_success
    assert_output "2"
}

@test "Max depth: base case — no loop, no code execution, flat LLM call" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/recursion"
    export RLM_MAX_DEPTH=2
    export RLM_DEPTH=2  # Already at max depth

    run "$RLM_BIN" "what is 2+2" < /dev/null
    assert_success

    # Should get the content from base.md on stdout
    assert_output --partial "4"

    local stdout_file="$TEST_TEMP/stdout.txt"
    local stderr_file="$TEST_TEMP/stderr.txt"
    _RLM_TREE_ROOT="$_RLM_TREE_ROOT" _RLM_MOCK_DIR="$_RLM_MOCK_DIR" \
        RLM_MAX_DEPTH=2 RLM_DEPTH=2 \
        "$RLM_BIN" "what is 2+2" > "$stdout_file" 2> "$stderr_file" < /dev/null

    # stdout should have the base case response
    run cat "$stdout_file"
    assert_output --partial "4"

    # stderr should have the base case diagnostic
    run cat "$stderr_file"
    assert_output --partial "base case"

    # No workdir should be created (base case exits before workdir setup)
    assert [ ! -d "$_RLM_TREE_ROOT" ] || [ -z "$(ls -A "$_RLM_TREE_ROOT" 2>/dev/null)" ]
}

@test "Max depth: simpler system prompt — base case uses BASE_SYSTEM_PROMPT" {
    # We verify this indirectly: at max depth, the mock base case path runs
    # (no code execution, no RETURN). In real mode, call_llm gets BASE_SYSTEM_PROMPT.
    # Here we just verify the base case path is taken and no code is executed.
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/recursion"
    export RLM_MAX_DEPTH=1
    export RLM_DEPTH=1

    # The base case should NOT execute code blocks, even if base.md contained them.
    # It just prints the content directly.
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    # Output comes from base.md, not from code execution
    assert_output --partial "4"

    # No trace directory should be created
    assert [ ! -d "$_RLM_TREE_ROOT" ] || [ -z "$(ls -A "$_RLM_TREE_ROOT" 2>/dev/null)" ]
}

@test "Recursive rlm call returns to parent: child RETURN value captured" {
    # Parent mock: code block invokes rlm with a child-specific mock dir
    # Child mock: returns "child-result-42"
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/recursion-parent"
    export _RLM_CHILD_MOCK_DIR="$PROJECT_ROOT/test/fixtures/recursion-child"
    export RLM_MAX_DEPTH=5  # Enough room for recursion

    run "$RLM_BIN" "parent query" < /dev/null
    assert_success
    assert_output "child-result-42"
}

@test "Sibling depth isolation: two children at depth 1 don't see each other's RLM_DEPTH" {
    # Run two independent rlm invocations at the same depth and verify they
    # each see the correct depth without interference.
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "$RLM_DEPTH"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_DEPTH=1  # Both start at depth 1

    # First child
    local tree1="$TEST_TEMP/tree1"
    export _RLM_TREE_ROOT="$tree1"
    run "$RLM_BIN" "child 1" < /dev/null
    assert_success
    local depth1="$output"

    # Second child
    local tree2="$TEST_TEMP/tree2"
    export _RLM_TREE_ROOT="$tree2"
    run "$RLM_BIN" "child 2" < /dev/null
    assert_success
    local depth2="$output"

    # Both should see depth 2 (inherited 1, incremented to 2)
    assert_equal "$depth1" "2"
    assert_equal "$depth2" "2"
}
