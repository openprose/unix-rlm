#!/usr/bin/env bats
# test/parallel.bats — Parallel invocation tests

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    mkdir -p "$_RLM_TREE_ROOT"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "Background rlm processes: three rlm & invocations, wait, all complete" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"

    "$RLM_BIN" "query 1" < /dev/null > "$TEST_TEMP/out1.txt" 2>"$TEST_TEMP/err1.txt" &
    local pid1=$!
    "$RLM_BIN" "query 2" < /dev/null > "$TEST_TEMP/out2.txt" 2>"$TEST_TEMP/err2.txt" &
    local pid2=$!
    "$RLM_BIN" "query 3" < /dev/null > "$TEST_TEMP/out3.txt" 2>"$TEST_TEMP/err3.txt" &
    local pid3=$!

    wait "$pid1"
    local status1=$?
    wait "$pid2"
    local status2=$?
    wait "$pid3"
    local status3=$?

    assert [ "$status1" -eq 0 ]
    assert [ "$status2" -eq 0 ]
    assert [ "$status3" -eq 0 ]

    assert [ -s "$TEST_TEMP/out1.txt" ]
    assert [ -s "$TEST_TEMP/out2.txt" ]
    assert [ -s "$TEST_TEMP/out3.txt" ]
}

@test "Separate workdirs: each parallel invocation has a distinct PID-based workdir" {
    export _RLM_MOCK_DIR="$PROJECT_ROOT/test/fixtures/simple-return"

    "$RLM_BIN" "query 1" < /dev/null > /dev/null 2>&1 &
    local pid1=$!
    "$RLM_BIN" "query 2" < /dev/null > /dev/null 2>&1 &
    local pid2=$!
    "$RLM_BIN" "query 3" < /dev/null > /dev/null 2>&1 &
    local pid3=$!

    wait "$pid1" "$pid2" "$pid3"

    local pid_dirs
    pid_dirs=("$_RLM_TREE_ROOT"/*)
    local count=${#pid_dirs[@]}

    assert [ "$count" -eq 3 ]

    for dir in "${pid_dirs[@]}"; do
        assert [ -d "$dir/trace" ]
        assert [ -d "$dir/children" ]
        assert [ -f "$dir/query" ]
        assert [ -f "$dir/trace/001-response.md" ]
    done
}

@test "Separate answer files: no RETURN races — each writes to its own answer file" {
    local mock1="$TEST_TEMP/mock1"
    local mock2="$TEST_TEMP/mock2"
    local mock3="$TEST_TEMP/mock3"
    mkdir -p "$mock1" "$mock2" "$mock3"
    printf '%s' '```repl
RETURN "answer-alpha"
```' > "$mock1/1.md"
    printf '%s' '```repl
RETURN "answer-beta"
```' > "$mock2/1.md"
    printf '%s' '```repl
RETURN "answer-gamma"
```' > "$mock3/1.md"

    _RLM_MOCK_DIR="$mock1" "$RLM_BIN" "q1" < /dev/null > "$TEST_TEMP/out1.txt" 2>&1 &
    local pid1=$!
    _RLM_MOCK_DIR="$mock2" "$RLM_BIN" "q2" < /dev/null > "$TEST_TEMP/out2.txt" 2>&1 &
    local pid2=$!
    _RLM_MOCK_DIR="$mock3" "$RLM_BIN" "q3" < /dev/null > "$TEST_TEMP/out3.txt" 2>&1 &
    local pid3=$!

    wait "$pid1" "$pid2" "$pid3"

    run cat "$TEST_TEMP/out1.txt"
    assert_output "answer-alpha"

    run cat "$TEST_TEMP/out2.txt"
    assert_output "answer-beta"

    run cat "$TEST_TEMP/out3.txt"
    assert_output "answer-gamma"

    local pid_dirs=("$_RLM_TREE_ROOT"/*)
    local found_alpha=false
    local found_beta=false
    local found_gamma=false
    for dir in "${pid_dirs[@]}"; do
        if [ -f "$dir/answer" ]; then
            local answer
            answer=$(cat "$dir/answer")
            case "$answer" in
                "answer-alpha") found_alpha=true ;;
                "answer-beta") found_beta=true ;;
                "answer-gamma") found_gamma=true ;;
            esac
        fi
    done

    assert [ "$found_alpha" = true ]
    assert [ "$found_beta" = true ]
    assert [ "$found_gamma" = true ]
}

@test "Stdout capture: rlm > /tmp/result_n captures each answer independently" {
    local mock1="$TEST_TEMP/mock-cap1"
    local mock2="$TEST_TEMP/mock-cap2"
    local mock3="$TEST_TEMP/mock-cap3"
    mkdir -p "$mock1" "$mock2" "$mock3"
    printf '%s' '```repl
RETURN "result-one"
```' > "$mock1/1.md"
    printf '%s' '```repl
RETURN "result-two"
```' > "$mock2/1.md"
    printf '%s' '```repl
RETURN "result-three"
```' > "$mock3/1.md"

    local result1="$TEST_TEMP/result_1"
    local result2="$TEST_TEMP/result_2"
    local result3="$TEST_TEMP/result_3"

    _RLM_MOCK_DIR="$mock1" "$RLM_BIN" "q1" < /dev/null > "$result1" 2>/dev/null &
    local p1=$!
    _RLM_MOCK_DIR="$mock2" "$RLM_BIN" "q2" < /dev/null > "$result2" 2>/dev/null &
    local p2=$!
    _RLM_MOCK_DIR="$mock3" "$RLM_BIN" "q3" < /dev/null > "$result3" 2>/dev/null &
    local p3=$!

    wait "$p1" "$p2" "$p3"

    run cat "$result1"
    assert_output "result-one"

    run cat "$result2"
    assert_output "result-two"

    run cat "$result3"
    assert_output "result-three"
}
