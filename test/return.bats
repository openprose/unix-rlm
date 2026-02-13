#!/usr/bin/env bats
# test/return.bats — RETURN mechanism tests

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true

    # Set up a workdir for direct function testing
    export RLM_WORKDIR="$TEST_TEMP/rlm/tree/$$"
    export RLM_ANSWER_FILE="$RLM_WORKDIR/answer"
    mkdir -p "$RLM_WORKDIR/trace" "$RLM_WORKDIR/children"

    # Source extract_code_blocks and execute_block from the bash rlm script.
    # These white-box tests extract bash functions directly; use the bash script regardless of RLM_BIN.
    local bash_rlm="$PROJECT_ROOT/bin/rlm"
    eval "$(awk '/^extract_code_blocks\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$bash_rlm")"
    eval "$(awk '/^execute_block\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$bash_rlm")"
}

teardown() {
    rm -rf "$TEST_TEMP"
}

# Helper for e2e tests: use a separate tree root so the setup-created workdir
# does not interfere with finding the rlm-created workdir.
setup_e2e() {
    E2E_TREE_ROOT="$TEST_TEMP/e2e-tree"
    export _RLM_TREE_ROOT="$E2E_TREE_ROOT"
    unset RLM_WORKDIR
    unset RLM_ANSWER_FILE
}

@test "RETURN creates answer file" {
    # Create a code block that calls RETURN
    local response='```repl
RETURN "hello world"
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    # Execute the block
    execute_block "$blocks_dir/1.sh" 1 1 >/dev/null

    # Answer file should exist and contain the value
    assert_file_exist "$RLM_ANSWER_FILE"
    run cat "$RLM_ANSWER_FILE"
    assert_output "hello world"
}

@test "RETURN with empty string" {
    local response='```repl
RETURN ""
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    execute_block "$blocks_dir/1.sh" 1 1 >/dev/null

    # Answer file should exist but be empty
    assert_file_exist "$RLM_ANSWER_FILE"
    run cat "$RLM_ANSWER_FILE"
    assert_output ""
}

@test "RETURN with multiline value" {
    local response='```repl
RETURN "line one
line two
line three"
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    execute_block "$blocks_dir/1.sh" 1 1 >/dev/null

    assert_file_exist "$RLM_ANSWER_FILE"
    run cat "$RLM_ANSWER_FILE"
    assert_line --index 0 "line one"
    assert_line --index 1 "line two"
    assert_line --index 2 "line three"
}

@test "RETURN with special characters" {
    # Test quotes, backticks, dollar signs, backslashes
    local response='```repl
RETURN "quotes: '\''single'\'' and \"double\", backtick: \`, dollar: \$HOME, backslash: \\"
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    execute_block "$blocks_dir/1.sh" 1 1 >/dev/null

    assert_file_exist "$RLM_ANSWER_FILE"
    # The answer file should contain the special characters
    local content
    content=$(cat "$RLM_ANSWER_FILE")
    # Verify it's non-empty and contains some of the special chars
    assert [ -n "$content" ]
    # Check for specific characters in the output
    run cat "$RLM_ANSWER_FILE"
    assert_output --partial "quotes:"
    assert_output --partial "backtick:"
    assert_output --partial "dollar:"
}

# End-to-end tests

@test "end-to-end: RETURN in first iteration — exit 0 and answer on stdout" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    run "$RLM_BIN" "what is the answer?" < /dev/null
    assert_success
    assert_output "hello"
}

@test "end-to-end: trace files exist after run" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
}

@test "end-to-end: answer file exists at RLM_ANSWER_FILE" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    assert_file_exist "$workdir/answer"
    run cat "$workdir/answer"
    assert_output "hello"
}

@test "end-to-end: response trace matches mock fixture" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    run cat "$workdir/trace/001-response.md"
    assert_output --partial "I'll calculate that for you."
    assert_output --partial 'RETURN "hello"'
}

@test "end-to-end: query file written correctly" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    run "$RLM_BIN" "what is 2 + 2?" < /dev/null
    assert_success

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    run cat "$workdir/query"
    assert_output "what is 2 + 2?"
}

@test "end-to-end: mock file not found — exits non-zero" {
    setup_e2e
    # Use an empty mock dir so iteration 1 has no fixture file
    local empty_mock="$TEST_TEMP/empty-mock"
    mkdir -p "$empty_mock"
    export _RLM_MOCK_DIR="$empty_mock"

    run "$RLM_BIN" "query" < /dev/null
    assert_failure
}

# Multi-turn RETURN tests

@test "RETURN after multiple iterations: loop runs twice, second iteration returns" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/multi-turn"

    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "done"

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
    assert_file_exist "$workdir/trace/002-response.md"
}

@test "RETURN in second code block: single-block mode discards second block, RETURN in next iteration" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/return-in-second-block"

    # Capture stdout and stderr separately (single-block discard warning goes to stderr)
    local stdout_file="$TEST_TEMP/stdout-second-block.txt"
    local stderr_file="$TEST_TEMP/stderr-second-block.txt"
    _RLM_TREE_ROOT="$E2E_TREE_ROOT" _RLM_MOCK_DIR="$_RLM_MOCK_DIR" \
        "$RLM_BIN" "test query" > "$stdout_file" 2> "$stderr_file" < /dev/null
    local exit_code=$?

    assert [ "$exit_code" -eq 0 ]

    run cat "$stdout_file"
    assert_output "from-second-block"

    # stderr should contain the single-block discard warning
    run cat "$stderr_file"
    assert_output --partial "discarding 1 additional code block(s) (single-block mode)"

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    # First iteration output should contain the discard warning
    run cat "$workdir/trace/001-output.txt"
    assert_output --partial "extra code block(s) were discarded"

    # Second iteration should have the actual RETURN
    assert_file_exist "$workdir/trace/002-response.md"
}

@test "No implicit termination: response without RETURN continues the loop" {
    setup_e2e
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/no-implicit-termination"

    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "continued"

    local workdir
    workdir="$(find_workdir "$E2E_TREE_ROOT")"

    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
    assert_file_exist "$workdir/trace/002-response.md"
}
