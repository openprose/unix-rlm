# test/test_helper.bash — shared BATS test infrastructure for rlm

# Resolve the project root (parent of test/)
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
RLM_BIN="$PROJECT_ROOT/bin/rlm"

# Load BATS helper libraries
load "$TEST_DIR/lib/bats-support/load"
load "$TEST_DIR/lib/bats-assert/load"
load "$TEST_DIR/lib/bats-file/load"

# Run a command with a real pseudo-terminal on stdin (so [ ! -t 0 ] is false).
# Handles macOS vs Linux `script` syntax differences.
run_with_tty() {
    if [[ "$OSTYPE" == darwin* ]]; then
        script -q /dev/null "$@"
    else
        script -qc "$*" /dev/null
    fi
}

# Find the workdir after a run (PID-based, so we look for it).
# Accepts an optional tree root argument (defaults to $TEST_TEMP/rlm/tree).
find_workdir() {
    local tree_root="${1:-$TEST_TEMP/rlm/tree}"
    local pid_dirs=("$tree_root"/*)
    echo "${pid_dirs[0]}"
}

# Create a mock fixture directory with N response files.
# Usage: mock_dir=$(mock_responses "response 1" "response 2" ...)
# Returns the path to the mock directory on stdout.
mock_responses() {
    local dir="$TEST_TEMP/mock"
    mkdir -p "$dir"
    local i=1
    for resp in "$@"; do
        printf '%s' "$resp" > "$dir/$i.md"
        ((i++))
    done
    echo "$dir"
}
