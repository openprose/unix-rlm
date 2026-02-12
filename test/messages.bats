#!/usr/bin/env bats
# test/messages.bats — Message history (build_messages) tests

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

    # Source build_messages from the rlm script
    eval "$(awk '/^build_messages\(\)/{found=1; depth=0} found{print; if(/{/) depth++; if(/}/) depth--; if(found && depth==0 && /}/) exit}' "$RLM_BIN")"
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "First iteration: messages array is [{role: user, content: query}]" {
    printf '%s' "what is 2+2?" > "$RLM_WORKDIR/query"

    run build_messages
    assert_success

    local count
    count=$(echo "$output" | jq 'length')
    assert [ "$count" -eq 1 ]

    local role
    role=$(echo "$output" | jq -r '.[0].role')
    assert [ "$role" = "user" ]

    local content
    content=$(echo "$output" | jq -r '.[0].content')
    assert [ "$content" = "what is 2+2?" ]
}

@test "Second iteration: messages include assistant response + user output from iteration 1" {
    printf '%s' "test query" > "$RLM_WORKDIR/query"

    # Simulate iteration 1's trace files
    printf '%s' 'Here is some code:

```repl
echo "hello"
```' > "$RLM_WORKDIR/trace/001-response.md"
    printf '%s' "hello" > "$RLM_WORKDIR/trace/001-output.txt"

    run build_messages
    assert_success

    local count
    count=$(echo "$output" | jq 'length')
    assert [ "$count" -eq 3 ]

    local role0
    role0=$(echo "$output" | jq -r '.[0].role')
    assert [ "$role0" = "user" ]

    local role1
    role1=$(echo "$output" | jq -r '.[1].role')
    assert [ "$role1" = "assistant" ]
    local content1
    content1=$(echo "$output" | jq -r '.[1].content')
    assert [ "$content1" != "" ]

    local role2
    role2=$(echo "$output" | jq -r '.[2].role')
    assert [ "$role2" = "user" ]
    local content2
    content2=$(echo "$output" | jq -r '.[2].content')
    assert [ "$content2" = "hello" ]
}

@test "Messages derived from trace files: rebuild from disk, same result" {
    printf '%s' "test query" > "$RLM_WORKDIR/query"

    # Simulate 2 iterations of trace files
    printf '%s' 'First response

```repl
echo "step one"
```' > "$RLM_WORKDIR/trace/001-response.md"
    printf '%s' "step one" > "$RLM_WORKDIR/trace/001-output.txt"

    printf '%s' 'Second response

```repl
RETURN "done"
```' > "$RLM_WORKDIR/trace/002-response.md"
    printf '%s' "" > "$RLM_WORKDIR/trace/002-output.txt"

    # Call build_messages twice — both should produce identical results
    local result1
    result1=$(build_messages)
    local result2
    result2=$(build_messages)

    assert [ "$result1" = "$result2" ]

    # Should have 5 elements: query + 2 * (response + output)
    local count
    count=$(echo "$result1" | jq 'length')
    assert [ "$count" -eq 5 ]
}

@test "build_messages output is valid JSON" {
    printf '%s' "test query with \"quotes\" and \$pecial chars" > "$RLM_WORKDIR/query"

    # Add a trace with special characters in output
    printf '%s' 'Response with "quotes"

```repl
echo "hello \"world\""
```' > "$RLM_WORKDIR/trace/001-response.md"
    printf '%s' 'hello "world"' > "$RLM_WORKDIR/trace/001-output.txt"

    run build_messages
    assert_success

    # jq should parse it without errors
    run bash -c "echo '$output' | jq . > /dev/null 2>&1"
    assert_success
}
