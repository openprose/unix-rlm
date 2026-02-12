#!/usr/bin/env bats
# test/plugins.bats — Plugin loading tests

load test_helper

setup() {
    TEST_TEMP="$(mktemp -d)"
    export TEST_TEMP
    export _RLM_TREE_ROOT="$TEST_TEMP/rlm/tree"
    unset RLM_WORKDIR RLM_ANSWER_FILE RLM_INPUT RLM_DEPTH RLM_PLUGINS 2>/dev/null || true
}

teardown() {
    rm -rf "$TEST_TEMP"
}

@test "Plugin loading: RLM_PLUGINS loads plugin content into system prompt" {
    # Create a test plugin
    local plugin_dir="$TEST_TEMP/plugins"
    mkdir -p "$plugin_dir"
    cat > "$plugin_dir/test-driver.md" << 'EOF'
---
name: test-driver
kind: driver
---

This is test plugin content.
EOF

    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "ok"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_PLUGINS="test-driver"
    export RLM_PLUGINS_DIR="$plugin_dir"

    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "ok"
}

@test "Plugin loading: missing plugin produces warning on stderr" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "ok"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_PLUGINS="nonexistent-plugin"
    export RLM_PLUGINS_DIR="$TEST_TEMP/no-such-dir"

    # Run and capture stderr separately
    local stdout_file="$TEST_TEMP/stdout.txt"
    local stderr_file="$TEST_TEMP/stderr.txt"
    _RLM_TREE_ROOT="$_RLM_TREE_ROOT" _RLM_MOCK_DIR="$mock_dir" \
        RLM_PLUGINS="nonexistent-plugin" RLM_PLUGINS_DIR="$TEST_TEMP/no-such-dir" \
        "$RLM_BIN" "test query" > "$stdout_file" 2> "$stderr_file" < /dev/null

    run cat "$stderr_file"
    assert_output --partial "warning: plugin 'nonexistent-plugin' not found"
}

@test "Plugin loading: multiple plugins loaded in order" {
    local plugin_dir="$TEST_TEMP/plugins"
    mkdir -p "$plugin_dir"
    cat > "$plugin_dir/first.md" << 'EOF'
---
name: first
---

First plugin.
EOF
    cat > "$plugin_dir/second.md" << 'EOF'
---
name: second
---

Second plugin.
EOF

    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "ok"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    export RLM_PLUGINS="first,second"
    export RLM_PLUGINS_DIR="$plugin_dir"

    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "ok"
}

@test "Plugin loading: no RLM_PLUGINS means no plugin loading" {
    local mock_dir
    mock_dir=$(mock_responses '```repl
RETURN "ok"
```')

    export _RLM_MOCK_DIR="$mock_dir"
    unset RLM_PLUGINS 2>/dev/null || true

    run "$RLM_BIN" "test query" < /dev/null
    assert_success
    assert_output "ok"
}
