#!/usr/bin/env bats
# Smoke tests — basic rlm functionality with real LLM calls

load e2e_helper

teardown() {
    rm -rf "${E2E_TEMP:-}"
    rm -f /tmp/rlm-e2e-test.txt
}

@test "Simple math: rlm calculates 7 * 8 = 56" {
    run_rlm_with_retry 90 3 "What is 7 * 8? Calculate it in code and RETURN the numeric result."

    assert_success
    assert_output --partial "56"
}

@test "File creation: create, read, and RETURN file contents" {
    run_rlm_with_retry 90 3 "Create a file at /tmp/rlm-e2e-test.txt containing exactly the word 'hello' (no quotes, no newline). Then read it back and RETURN the contents."

    assert_success
    assert_output --partial "hello"
}

@test "Multi-step reasoning: count files in /etc" {
    run_rlm_with_retry 120 3 "List the files in /etc (not recursively, just the top level), count how many entries there are, and RETURN just the number."

    assert_success
    [[ "$output" =~ [0-9]+ ]]
}
