#!/usr/bin/env bats
# Filesystem persistence tests — state survives across code blocks and turns

load e2e_helper

teardown() {
    rm -rf "${E2E_TEMP:-}"
    rm -f /tmp/rlm-fs-test-*.txt
}

@test "Cross-block persistence: file written in one turn is readable in a later turn" {
    run_rlm_with_retry 90 3 \
        'First, write the word "persistence" to /tmp/rlm-fs-test-cross.txt (do NOT call RETURN yet). Then in your next response, read /tmp/rlm-fs-test-cross.txt and RETURN its contents.'

    assert_success
    assert_output --partial "persistence"
}

