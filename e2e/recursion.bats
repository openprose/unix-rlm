#!/usr/bin/env bats
# Recursion tests — rlm calls rlm to delegate sub-tasks

load e2e_helper

@test "Simple recursion: rlm calls rlm and returns the child result" {
    run_rlm_with_retry 120 3 'Use rlm to ask "what is 2+2" and RETURN whatever it says. Example: result=$(rlm "what is 2+2") then RETURN "$result"'

    assert_success
    assert_output --partial "4"
}

@test "Recursive decomposition: use rlm to process sub-tasks and combine results" {
    run_rlm_with_retry 180 3 'Run exactly this code:
result=$(rlm "Compute 15*15 in bash and RETURN just the number")
RETURN "$result"'

    assert_success
    assert_output --partial "225"

    local children_found=false
    for root_dir in "$_RLM_TREE_ROOT"/*/; do
        if [ -d "${root_dir}children" ] && [ -n "$(ls -A "${root_dir}children" 2>/dev/null)" ]; then
            children_found=true
            break
        fi
    done
    [ "$children_found" = true ]
}
