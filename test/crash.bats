#!/usr/bin/env bats
# test/crash.bats — Crash resilience tests

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    mkdir -p "$_RLM_TREE_ROOT"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH _RLM_RESUME_DIR 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "Kill mid-loop, trace persists: trace files from completed iterations survive" {
    local mock_dir="$TEST_TEMP/mock-kill"
    mkdir -p "$mock_dir"

    printf '%s' '```repl
echo "iteration one output"
```' > "$mock_dir/1.md"

    printf '%s' '```repl
echo "iteration two output"
```' > "$mock_dir/2.md"

    # No 3.md — simulates crash at iteration 3
    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_MAX_ITERATIONS=5
    run "$RLM_BIN" "crash test query" < /dev/null
    assert_failure

    local workdir
    workdir="$(find_workdir)"
    assert [ -d "$workdir" ]
    assert [ -d "$workdir/trace" ]

    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
    assert_file_exist "$workdir/trace/002-response.md"
    assert_file_exist "$workdir/trace/002-output.txt"
    assert_file_exist "$workdir/query"
    run cat "$workdir/query"
    assert_output "crash test query"
}

@test "Restart from trace: new rlm invocation with same workdir picks up from existing trace" {
    local mock_initial="$TEST_TEMP/mock-initial"
    mkdir -p "$mock_initial"
    printf '%s' '```repl
echo "step one done"
```' > "$mock_initial/1.md"
    printf '%s' '```repl
echo "step two done"
```' > "$mock_initial/2.md"
    # No 3.md — simulates crash at iteration 3

    export _RLM_MOCK_DIR="$mock_initial"
    export RLM_MAX_ITERATIONS=5

    "$RLM_BIN" "resumable query" < /dev/null > /dev/null 2>&1 || true

    local workdir
    workdir="$(find_workdir)"
    assert [ -d "$workdir" ]
    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/002-response.md"

    # Resume: new mock dir starts at iteration 3
    local mock_resume="$TEST_TEMP/mock-resume"
    mkdir -p "$mock_resume"
    printf '%s' '```repl
RETURN "resumed-successfully"
```' > "$mock_resume/3.md"

    export _RLM_MOCK_DIR="$mock_resume"
    export _RLM_RESUME_DIR="$workdir"
    export RLM_MAX_ITERATIONS=5

    run "$RLM_BIN" "resumable query" < /dev/null
    assert_success
    assert_output "resumed-successfully"

    assert_file_exist "$workdir/trace/003-response.md"
    assert_file_exist "$workdir/trace/001-response.md"
    assert_file_exist "$workdir/trace/001-output.txt"
    assert_file_exist "$workdir/trace/002-response.md"
    assert_file_exist "$workdir/trace/002-output.txt"
}

@test "Partial trace file handled: incomplete output.txt doesn't break build_messages" {
    export RLM_WORKDIR="$TEST_TEMP/rlm/tree/$$"
    export RLM_ANSWER_FILE="$RLM_WORKDIR/answer"
    mkdir -p "$RLM_WORKDIR/trace" "$RLM_WORKDIR/children"

    printf '%s' "partial trace query" > "$RLM_WORKDIR/query"

    printf '%s' 'Response 1

```repl
echo "complete"
```' > "$RLM_WORKDIR/trace/001-response.md"
    printf '%s' "complete" > "$RLM_WORKDIR/trace/001-output.txt"

    # Iteration 2: output file is empty (partial write / crash)
    printf '%s' 'Response 2

```repl
echo "this never finished"
```' > "$RLM_WORKDIR/trace/002-response.md"
    printf '%s' "" > "$RLM_WORKDIR/trace/002-output.txt"

    eval "$(awk '/^build_messages\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"

    run build_messages
    assert_success

    echo "$output" | jq . > /dev/null 2>&1
    assert [ $? -eq 0 ]

    local count
    count=$(echo "$output" | jq 'length')
    assert [ "$count" -eq 5 ]

    local last_content
    last_content=$(echo "$output" | jq -r '.[-1].content')
    assert [ "$last_content" = "" ]
}

@test "Partial trace file handled: missing output.txt skips that iteration pair" {
    export RLM_WORKDIR="$TEST_TEMP/rlm/tree/$$"
    export RLM_ANSWER_FILE="$RLM_WORKDIR/answer"
    mkdir -p "$RLM_WORKDIR/trace" "$RLM_WORKDIR/children"

    printf '%s' "missing output query" > "$RLM_WORKDIR/query"

    printf '%s' 'Response 1

```repl
echo "ok"
```' > "$RLM_WORKDIR/trace/001-response.md"
    printf '%s' "ok" > "$RLM_WORKDIR/trace/001-output.txt"

    # Iteration 2: output file MISSING (crash before output was written)
    printf '%s' 'Response 2

```repl
echo "crash before output"
```' > "$RLM_WORKDIR/trace/002-response.md"

    eval "$(awk '/^build_messages\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"

    run build_messages
    assert_success

    echo "$output" | jq . > /dev/null 2>&1
    assert [ $? -eq 0 ]
    local count
    count=$(echo "$output" | jq 'length')
    assert [ "$count" -eq 3 ]
}
