#!/usr/bin/env bats
# test/workdir.bats — directory structure tests for rlm

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "root workdir created with trace/ and children/ dirs" {
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local tree_root="$TEST_TEMP/rlm/tree"
    assert [ -d "$tree_root" ]

    local pid_dirs=("$tree_root"/*)
    assert [ ${#pid_dirs[@]} -eq 1 ]

    local workdir="${pid_dirs[0]}"
    assert [ -d "$workdir/trace" ]
    assert [ -d "$workdir/children" ]
}

@test "query file written" {
    run "$RLM_BIN" "what is the meaning of life" < /dev/null
    assert_success

    local tree_root="$TEST_TEMP/rlm/tree"
    local pid_dirs=("$tree_root"/*)
    local workdir="${pid_dirs[0]}"

    assert_file_exist "$workdir/query"
    run cat "$workdir/query"
    assert_output "what is the meaning of life"
}

@test "trace directory exists with trace files after run" {
    run "$RLM_BIN" "test query" < /dev/null
    assert_success

    local tree_root="$TEST_TEMP/rlm/tree"
    local pid_dirs=("$tree_root"/*)
    local workdir="${pid_dirs[0]}"

    assert_dir_exist "$workdir/trace"
    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
}

@test "child workdir created under parent" {
    run "$RLM_BIN" "parent query" < /dev/null
    assert_success

    local tree_root="$TEST_TEMP/rlm/tree"
    local pid_dirs=("$tree_root"/*)
    local parent_workdir="${pid_dirs[0]}"

    RLM_WORKDIR="$parent_workdir" run "$RLM_BIN" "child query" < /dev/null
    assert_success

    local child_dirs=("$parent_workdir/children"/*)
    assert [ -e "${child_dirs[0]}" ]

    local child_workdir="${child_dirs[0]}"
    assert [ -d "$child_workdir/trace" ]
    assert [ -d "$child_workdir/children" ]

    assert_file_exist "$child_workdir/query"
    run cat "$child_workdir/query"
    assert_output "child query"
}

@test "no cleanup on exit — workdir persists" {
    run "$RLM_BIN" "persist test" < /dev/null
    assert_success

    local tree_root="$TEST_TEMP/rlm/tree"
    local pid_dirs=("$tree_root"/*)
    local workdir="${pid_dirs[0]}"

    assert [ -d "$workdir" ]
    assert [ -d "$workdir/trace" ]
    assert [ -d "$workdir/children" ]
    assert_file_exist "$workdir/query"
}
