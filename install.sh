#!/usr/bin/env bash
set -euo pipefail

# install.sh — Unix RLM installer
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/openprose/unix-rlm/main/install.sh | bash
#   PREFIX=/custom/path ./install.sh
#
# Installs the `rlm` script to $PREFIX/bin/rlm (default: /usr/local/bin/rlm).
# Idempotent — re-running overwrites cleanly.

# --- Configuration -----------------------------------------------------------

PREFIX="${PREFIX:-/usr/local}"
INSTALL_DIR="$PREFIX/bin"
REPO_BASE="https://raw.githubusercontent.com/openprose/unix-rlm/main/bin"

# --- Helpers -----------------------------------------------------------------

info() { printf '  %s\n' "$@"; }
error() { printf 'Error: %s\n' "$@" >&2; exit 1; }

# --- Dependency Checks -------------------------------------------------------

check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        error "$1 is required but not found. Please install $1 first."
    fi
}

check_bash_version() {
    local bash_version
    bash_version="${BASH_VERSINFO[0]}"
    if [ "$bash_version" -lt 4 ]; then
        error "bash 4+ is required (found bash $bash_version). Please upgrade bash."
    fi
}

info "Checking dependencies..."
check_bash_version
check_command jq
check_command curl
info "All dependencies satisfied."

# --- Determine Install Source ------------------------------------------------

# If run from a cloned repo (bin/rlm exists relative to this script), copy
# the local file. Otherwise, download from GitHub.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$SCRIPT_DIR/bin"

# --- Install -----------------------------------------------------------------

info "Installing rlm, llm, and _rlm-common.sh to $INSTALL_DIR/..."

# Create the install directory if it doesn't exist
if [ ! -d "$INSTALL_DIR" ]; then
    mkdir -p "$INSTALL_DIR" 2>/dev/null || {
        error "Cannot create $INSTALL_DIR. Try: sudo PREFIX=$PREFIX $0"
    }
fi

# Check write permission
if [ ! -w "$INSTALL_DIR" ]; then
    error "Cannot write to $INSTALL_DIR. Try: sudo PREFIX=$PREFIX $0"
fi

if [ -f "$LOCAL_BIN/rlm" ]; then
    # Install from local repo
    cp "$LOCAL_BIN/rlm" "$INSTALL_DIR/rlm"
    cp "$LOCAL_BIN/llm" "$INSTALL_DIR/llm"
    cp "$LOCAL_BIN/_rlm-common.sh" "$INSTALL_DIR/_rlm-common.sh"
else
    # Download from GitHub
    info "Downloading from $REPO_BASE/..."
    curl -sSL "$REPO_BASE/rlm" -o "$INSTALL_DIR/rlm" || {
        error "Failed to download rlm. Check your internet connection."
    }
    curl -sSL "$REPO_BASE/llm" -o "$INSTALL_DIR/llm" || {
        error "Failed to download llm. Check your internet connection."
    }
    curl -sSL "$REPO_BASE/_rlm-common.sh" -o "$INSTALL_DIR/_rlm-common.sh" || {
        error "Failed to download _rlm-common.sh. Check your internet connection."
    }
fi

chmod +x "$INSTALL_DIR/rlm" "$INSTALL_DIR/llm"

# --- Verify ------------------------------------------------------------------

if [ ! -x "$INSTALL_DIR/rlm" ]; then
    error "Installation failed — $INSTALL_DIR/rlm is not executable."
fi
if [ ! -x "$INSTALL_DIR/llm" ]; then
    error "Installation failed — $INSTALL_DIR/llm is not executable."
fi
if [ ! -f "$INSTALL_DIR/_rlm-common.sh" ]; then
    error "Installation failed — $INSTALL_DIR/_rlm-common.sh is missing."
fi

# --- Success -----------------------------------------------------------------

echo ""
echo "Unix RLM installed successfully!"
echo ""
info "Location: $INSTALL_DIR/{rlm,llm,_rlm-common.sh}"
info ""
info "Quick start:"
info "  export OPENROUTER_API_KEY=\"sk-or-v1-...\""
info "  rlm \"What is 2 + 2?\""
info ""
info "Documentation: https://github.com/openprose/unix-rlm"
