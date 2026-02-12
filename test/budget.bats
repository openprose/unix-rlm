#!/usr/bin/env bats
# test/budget.bats — Iteration budget decay tests

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

@test "Budget decay: root (depth 0) gets full budget" {
    local mock_dir="$TEST_TEMP/mock"
    mkdir -p "$mock_dir"
    for i in $(seq 1 5); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=5

    run "$RLM_BIN" "test query" < /dev/null
    assert_failure
    assert_output --partial "max iterations (5) reached without RETURN"
}

@test "Budget decay: depth 1 gets min(maxIters, 7)" {
    local mock_dir="$TEST_TEMP/mock"
    mkdir -p "$mock_dir"
    for i in $(seq 1 15); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=15
    export RLM_DEPTH=1  # Will become _SELF_DEPTH=1 after increment

    run "$RLM_BIN" "test query" < /dev/null
    assert_failure
    assert_output --partial "max iterations (7) reached without RETURN"
}

@test "Budget decay: depth 2 gets min(maxIters, 4)" {
    local mock_dir="$TEST_TEMP/mock"
    mkdir -p "$mock_dir"
    for i in $(seq 1 15); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=15
    export RLM_DEPTH=2

    run "$RLM_BIN" "test query" < /dev/null
    assert_failure
    assert_output --partial "max iterations (4) reached without RETURN"
}

@test "Budget decay: depth 3+ gets min(maxIters, 3)" {
    local mock_dir="$TEST_TEMP/mock"
    mkdir -p "$mock_dir"
    for i in $(seq 1 15); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=15
    export RLM_DEPTH=3
    export RLM_MAX_DEPTH=10  # High enough to not hit base case

    run "$RLM_BIN" "test query" < /dev/null
    assert_failure
    assert_output --partial "max iterations (3) reached without RETURN"
}

@test "Budget decay: depth 1 with maxIters=3 gets 3 (not 7)" {
    local mock_dir="$TEST_TEMP/mock"
    mkdir -p "$mock_dir"
    for i in $(seq 1 5); do
        printf '```repl\necho "iteration %d"\n```' "$i" > "$mock_dir/$i.md"
    done

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=3
    export RLM_DEPTH=1

    run "$RLM_BIN" "test query" < /dev/null
    assert_failure
    assert_output --partial "max iterations (3) reached without RETURN"
}
