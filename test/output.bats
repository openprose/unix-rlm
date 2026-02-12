#!/usr/bin/env bats
# test/output.bats — Output capture and truncation tests

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

    # Source extract_code_blocks, execute_block, and truncate_output from the rlm script.
    eval "$(awk '/^extract_code_blocks\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"
    eval "$(awk '/^execute_block\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"
    eval "$(awk '/^truncate_output\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "stdout captured" {
    local response='```repl
echo "hello"
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    run execute_block "$blocks_dir/1.sh" 1 1
    assert_success
    assert_output "hello"

    assert_file_exist "$RLM_WORKDIR/trace/001-output.txt"
    run cat "$RLM_WORKDIR/trace/001-output.txt"
    assert_output "hello"
}

@test "stderr captured" {
    local response='```repl
echo "err" >&2
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    run execute_block "$blocks_dir/1.sh" 1 1
    assert_success
    assert_output "err"

    run cat "$RLM_WORKDIR/trace/001-output.txt"
    assert_output "err"
}

@test "stdout + stderr merged" {
    local response='```repl
echo "out"
echo "err" >&2
echo "more out"
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    run execute_block "$blocks_dir/1.sh" 1 1
    assert_success
    assert_output --partial "out"
    assert_output --partial "err"
    assert_output --partial "more out"
}

@test "Exit code 0: no prefix" {
    local response='```repl
echo "success"
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    run execute_block "$blocks_dir/1.sh" 1 1
    assert_success
    assert_output "success"
    # Must NOT contain any [Exit code: ...] prefix
    refute_output --partial "[Exit code:"
}

@test "Exit code non-zero: prefix added" {
    local response='```repl
echo "some output"
exit 1
```'
    local blocks_dir
    blocks_dir=$(echo "$response" | extract_code_blocks)

    run execute_block "$blocks_dir/1.sh" 1 1
    assert_success  # execute_block itself always returns 0
    assert_line --index 0 "[Exit code: 1]"
    assert_output --partial "some output"

    run cat "$RLM_WORKDIR/trace/001-output.txt"
    assert_line --index 0 "[Exit code: 1]"
    assert_output --partial "some output"
}

# Truncation tests

@test "Truncation: large output gets head + tail + truncation notice" {
    # Generate output that exceeds the line threshold
    # Use a low threshold for testing
    local large_output=""
    for i in $(seq 1 200); do
        large_output="${large_output}line $i: some data for testing
"
    done

    local trace_path="$RLM_WORKDIR/trace/001-output.txt"
    printf '%s' "$large_output" > "$trace_path"

    # Call truncate_output with a low line threshold
    export _RLM_TRUNCATE_MAX_LINES=100
    export _RLM_TRUNCATE_MAX_BYTES=999999
    export _RLM_TRUNCATE_HEAD=50
    export _RLM_TRUNCATE_TAIL=20

    run truncate_output "$large_output" "$trace_path"
    assert_success

    assert_output --partial "[Output truncated. Full output:"
    assert_output --partial "First 50 lines:"
    assert_output --partial "Last 20 lines:"
    assert_output --partial "line 1:"
    assert_output --partial "line 200:"
    refute_output --partial "line 100:"
}

@test "Truncation: full output in trace file" {
    # End-to-end test: generate large output via the fixture
    # Use a separate tree root to avoid interference with setup-created workdir
    local e2e_tree="$TEST_TEMP/e2e-tree"
    export _RLM_TREE_ROOT="$e2e_tree"
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/large-output"
    # Use a low truncation threshold so the 2000-line output triggers it
    export _RLM_TRUNCATE_MAX_LINES=100

    unset RLM_WORKDIR
    unset RLM_ANSWER_FILE

    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local pid_dirs=("$e2e_tree"/*)
    local workdir="${pid_dirs[0]}"

    assert_file_exist "$workdir/trace/001-output.txt"
    local line_count
    line_count=$(wc -l < "$workdir/trace/001-output.txt" | tr -d ' ')
    assert [ "$line_count" -ge 1999 ]

    assert_file_exist "$workdir/trace/001-output-truncated.txt"
}

@test "Truncation notice includes path and size" {
    # Generate output exceeding the threshold
    local large_output=""
    for i in $(seq 1 200); do
        large_output="${large_output}line $i: padding data for size test
"
    done

    local trace_path="/some/path/trace/001-output.txt"

    export _RLM_TRUNCATE_MAX_LINES=100
    export _RLM_TRUNCATE_MAX_BYTES=999999
    export _RLM_TRUNCATE_HEAD=50
    export _RLM_TRUNCATE_TAIL=20

    run truncate_output "$large_output" "$trace_path"
    assert_success

    assert_output --partial "$trace_path"
    assert_output --partial "KB"
    assert_output --partial "200 lines"
}
