#!/usr/bin/env bats
# test/loop.bats — Multi-turn loop mechanics tests

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

@test "Multi-iteration loop: LLM needs 3 turns to answer" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/three-turn"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "three-turn-done"

    local workdir
    workdir="$(find_workdir)"

    # All 3 iterations should have trace files
    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
    assert_file_exist "$workdir/trace/002-response.md"
    assert_file_exist "$workdir/trace/002-output.txt"
    assert_file_exist "$workdir/trace/003-response.md"
}

@test "Output fed back as user message: iteration 1 stdout appears in iteration 2 messages" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/multi-turn"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local workdir
    workdir="$(find_workdir)"

    # Iteration 1's output should be in the trace (it ran "echo gathering information...")
    run cat "$workdir/trace/001-output.txt"
    assert_output --partial "gathering information"

    # The output file exists and was used by build_messages for the second call
    assert_file_exist "$workdir/trace/001-output.txt"
    assert_file_exist "$workdir/trace/002-response.md"
}

@test "Error recovery: code exits non-zero, loop continues, LLM self-corrects" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/error-recovery"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "recovered"

    local workdir
    workdir="$(find_workdir)"

    # First iteration should have exited non-zero
    run cat "$workdir/trace/001-output.txt"
    assert_output --partial "[Exit code: 1]"

    # Second iteration should have recovered
    assert_file_exist "$workdir/trace/002-response.md"
}

@test "Exit code prepended on error: [Exit code: 1] appears in feedback to LLM" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/error-recovery"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local workdir
    workdir="$(find_workdir)"

    # The first iteration's output should start with [Exit code: 1]
    run cat "$workdir/trace/001-output.txt"
    assert_line --index 0 --partial "[Exit code: 1]"
}

@test "No-code turn: one retry — prose response gets feedback, second chance succeeds" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/no-code-retry"
    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "42"

    local workdir
    workdir="$(find_workdir)"

    # First iteration should have no-code feedback
    run cat "$workdir/trace/001-output.txt"
    assert_output --partial "no executable code blocks"

    # Second iteration should have succeeded
    assert_file_exist "$workdir/trace/002-response.md"
}

@test "No-code turn: throw on second failure — two prose responses exits non-zero" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/no-code-fail"
    run "$RLM_BIN" "test query" < /dev/null
    assert_failure

    # stderr should explain why
    assert_output --partial "two consecutive responses with no code blocks"
}

@test "Max iterations: loop exhausts RLM_MAX_ITERATIONS, exits 1, stderr diagnostic" {
    # Create a mock that never calls RETURN (just echoes each time)
    local mock_dir="$TEST_TEMP/mock-max-iter"
    mkdir -p "$mock_dir"
    for i in $(seq 1 3); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=3

    run "$RLM_BIN" "test query" < /dev/null
    assert_failure

    # stderr should contain the diagnostic
    assert_output --partial "max iterations (3) reached without RETURN"
}

@test "Max iterations: stdout empty — no answer produced" {
    # Create a mock that never calls RETURN
    local mock_dir="$TEST_TEMP/mock-max-iter-empty"
    mkdir -p "$mock_dir"
    for i in $(seq 1 3); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=3

    # Capture stdout and stderr separately
    local stdout_file="$TEST_TEMP/stdout.txt"
    local stderr_file="$TEST_TEMP/stderr.txt"
    _RLM_TREE_ROOT="$_RLM_TREE_ROOT" _RLM_MOCK_DIR="$mock_dir" RLM_MAX_ITERATIONS=3 \
        "$RLM_BIN" "test query" > "$stdout_file" 2> "$stderr_file" < /dev/null || true

    # stdout should be empty (no answer produced)
    local stdout_content
    stdout_content=$(cat "$stdout_file")
    assert [ -z "$stdout_content" ]

    # stderr should have the diagnostic
    run cat "$stderr_file"
    assert_output --partial "max iterations (3) reached without RETURN"
}

@test "Multiple code blocks per response: only first block executes (single-block mode)" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/multi-block"

    # Capture stdout and stderr separately to avoid mixing them
    local stdout_file="$TEST_TEMP/stdout.txt"
    local stderr_file="$TEST_TEMP/stderr.txt"
    _RLM_TREE_ROOT="$_RLM_TREE_ROOT" _RLM_MOCK_DIR="$_RLM_MOCK_DIR" \
        "$RLM_BIN" "test query" > "$stdout_file" 2> "$stderr_file" < /dev/null
    local exit_code=$?

    assert [ "$exit_code" -eq 0 ]

    # stdout should have the answer
    run cat "$stdout_file"
    assert_output "multi-block-done"

    # stderr should contain the single-block discard warning
    run cat "$stderr_file"
    assert_output --partial "discarding 1 additional code block(s) (single-block mode)"

    local workdir
    workdir="$(find_workdir)"

    assert_file_exist "$workdir/trace/001-output.txt"

    # First iteration output (fed back to LLM) should contain the discard warning
    run cat "$workdir/trace/001-output.txt"
    assert_output --partial "extra code block(s) were discarded"
}

@test "RETURN stops remaining blocks: block 1 calls RETURN, block 2 does not execute" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/return-stops-blocks"

    # Clean up any leftover sentinel file
    rm -f /tmp/rlm-should-not-exist

    # Capture stdout and stderr separately (single-block discard warning goes to stderr)
    local stdout_file="$TEST_TEMP/stdout-return.txt"
    local stderr_file="$TEST_TEMP/stderr-return.txt"
    _RLM_TREE_ROOT="$_RLM_TREE_ROOT" _RLM_MOCK_DIR="$_RLM_MOCK_DIR" \
        "$RLM_BIN" "test query" > "$stdout_file" 2> "$stderr_file" < /dev/null
    local exit_code=$?

    assert [ "$exit_code" -eq 0 ]

    run cat "$stdout_file"
    assert_output "stopped-early"

    # The second block should NOT have executed — it would have created this file
    assert [ ! -f /tmp/rlm-should-not-exist ]

    # stderr should contain the single-block discard warning
    run cat "$stderr_file"
    assert_output --partial "discarding 1 additional code block(s) (single-block mode)"
}
