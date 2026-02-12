#!/usr/bin/env bats
# test/stdin.bats — piped input (stdin) handling tests for rlm

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    # Provide a mock fixture so the loop can complete successfully
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "piped input saved to file" {
    run bash -c "echo 'hello from stdin' | _RLM_TREE_ROOT='$_RLM_TREE_ROOT' _RLM_MOCK_DIR='$_RLM_MOCK_DIR' '$RLM_BIN' 'process this'"
    assert_success

    local workdir
    workdir="$(find_workdir)"
    assert_file_exist "$workdir/input"
    run cat "$workdir/input"
    assert_output "hello from stdin"
}

@test "RLM_INPUT exported" {
    # We verify RLM_INPUT is set by checking the input file exists at the expected path
    run bash -c "echo 'test data' | _RLM_TREE_ROOT='$_RLM_TREE_ROOT' _RLM_MOCK_DIR='$_RLM_MOCK_DIR' '$RLM_BIN' 'check input'"
    assert_success

    local workdir
    workdir="$(find_workdir)"
    # The input file should exist (RLM_INPUT points to $RLM_WORKDIR/input)
    assert_file_exist "$workdir/input"
}

@test "no pipe = no input file" {
    # Use run_with_tty to run rlm with a real pseudo-terminal on stdin,
    # so [ ! -t 0 ] is false and stdin handling is skipped.
    run run_with_tty bash -c "export _RLM_TREE_ROOT='$_RLM_TREE_ROOT'; export _RLM_MOCK_DIR='$_RLM_MOCK_DIR'; '$RLM_BIN' 'no stdin here'"
    assert_success

    local workdir
    workdir="$(find_workdir)"
    # input file should NOT exist when stdin is a terminal
    assert [ ! -f "$workdir/input" ]
}

@test "large input handled (10MB)" {
    # Generate ~10MB of data
    local input_file="$TEST_TEMP/large_input.txt"
    dd if=/dev/urandom bs=1024 count=10240 2>/dev/null | base64 > "$input_file"
    local expected_size
    expected_size=$(wc -c < "$input_file" | tr -d ' ')

    run bash -c "cat '$input_file' | _RLM_TREE_ROOT='$_RLM_TREE_ROOT' _RLM_MOCK_DIR='$_RLM_MOCK_DIR' '$RLM_BIN' 'handle large input'"
    assert_success

    local workdir
    workdir="$(find_workdir)"
    assert_file_exist "$workdir/input"

    # Verify size matches
    local actual_size
    actual_size=$(wc -c < "$workdir/input" | tr -d ' ')
    assert [ "$actual_size" -eq "$expected_size" ]
}

@test "input file accessible — content matches" {
    local test_content='line 1
line 2
line 3 with special chars'
    run bash -c "printf '%s' '$test_content' | _RLM_TREE_ROOT='$_RLM_TREE_ROOT' _RLM_MOCK_DIR='$_RLM_MOCK_DIR' '$RLM_BIN' 'verify content'"
    assert_success

    local workdir
    workdir="$(find_workdir)"
    assert_file_exist "$workdir/input"
    run cat "$workdir/input"
    assert_output "$test_content"
}
