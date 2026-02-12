E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$E2E_DIR/.." && pwd)"
RLM_BIN="$PROJECT_ROOT/bin/rlm"

load "$PROJECT_ROOT/test/lib/bats-support/load"
load "$PROJECT_ROOT/test/lib/bats-assert/load"

# macOS: gtimeout from coreutils
if command -v timeout >/dev/null 2>&1; then
    _TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    _TIMEOUT_CMD="gtimeout"
else
    _TIMEOUT_CMD=""
fi

_load_api_key() {
    if [ -z "${OPENROUTER_API_KEY:-}" ] && [ ! -f /etc/rlm/api-key ]; then
        local env_file="$PROJECT_ROOT/../.env"
        if [ -f "$env_file" ]; then
            # shellcheck disable=SC1090
            source "$env_file"
            export OPENROUTER_API_KEY
        fi
    fi
}

_require_api_key() {
    _load_api_key
    if [ -z "${OPENROUTER_API_KEY:-}" ] && [ ! -f /etc/rlm/api-key ]; then
        skip "No API key found, skipping E2E tests"
    fi
}

setup() {
    _require_api_key
    E2E_TEMP="$(mktemp -d)"
    export _RLM_TREE_ROOT="$E2E_TEMP/rlm/tree"
    mkdir -p "$_RLM_TREE_ROOT"
    export RLM_MAX_ITERATIONS=5
    export RLM_MAX_DEPTH=2
    export RLM_MAX_TOKENS=4096
    unset _RLM_MOCK_DIR 2>/dev/null || true
    unset RLM_WORKDIR 2>/dev/null || true
    unset RLM_DEPTH 2>/dev/null || true
    unset _RLM_RESUME_DIR 2>/dev/null || true
}

teardown() {
    rm -rf "${E2E_TEMP:-}"
}

run_rlm_with_retry() {
    local timeout_secs="$1"
    local max_retries="$2"
    local stdin_file=""

    if [[ "$3" == "--stdin-file" ]]; then
        stdin_file="$4"
        shift 4
    else
        shift 2
    fi

    local query="$1"
    local attempt=1

    while [ "$attempt" -le "$max_retries" ]; do
        # Reset tree root for each attempt to avoid stale trace files
        rm -rf "$_RLM_TREE_ROOT"
        mkdir -p "$_RLM_TREE_ROOT"

        if [ -n "$stdin_file" ]; then
            if [ -n "$_TIMEOUT_CMD" ]; then
                run bash -c '"$1" "$2" "$3" "$4" < "$5"' _ \
                    "$_TIMEOUT_CMD" "$timeout_secs" "$RLM_BIN" "$query" "$stdin_file"
            else
                run bash -c '"$1" "$2" < "$3"' _ \
                    "$RLM_BIN" "$query" "$stdin_file"
            fi
        else
            if [ -n "$_TIMEOUT_CMD" ]; then
                run "$_TIMEOUT_CMD" "$timeout_secs" "$RLM_BIN" "$query"
            else
                run "$RLM_BIN" "$query"
            fi
        fi

        if [ "$status" -eq 0 ]; then
            return 0
        fi

        attempt=$((attempt + 1))
        if [ "$attempt" -le "$max_retries" ]; then
            echo "# Attempt $((attempt - 1)) failed (status=$status), retrying... ($attempt/$max_retries)" >&3
        fi
    done
    return 0  # Let the assertions handle the failure
}
