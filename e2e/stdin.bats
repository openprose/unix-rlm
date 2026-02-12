#!/usr/bin/env bats
# Piped input tests — rlm handles stdin via $RLM_INPUT

load e2e_helper

@test "Pipe small input: echo secret word and ask rlm to find it" {
    local input_file="$E2E_TEMP/stdin_input.txt"
    printf '%s\n' "the secret word is banana" > "$input_file"

    run_rlm_with_retry 90 3 --stdin-file "$input_file" \
        'Data was piped to you. Read $RLM_INPUT, extract the word after "secret word is", and RETURN that word. Use: word=$(cat "$RLM_INPUT" | grep -o "secret word is [a-z]*" | awk "{print \$4}") then RETURN "$word"'

    assert_success
    assert_output --partial "banana"
}

@test "Pipe file input: count lines of /etc/passwd" {
    run_rlm_with_retry 120 3 --stdin-file "/etc/passwd" \
        'How many lines are in this file? Count the lines of $RLM_INPUT using wc -l. RETURN only the number.'

    assert_success
    [[ "$output" =~ [0-9]+ ]]
}
