#!/usr/bin/env bash
# ===========================================================================
# qa-helpers.sh — shared utilities for Zepto QA test scripts
# ===========================================================================
# Source this file at the top of every test script:
#   source "$(dirname "$0")/../lib/qa-helpers.sh"
#
# Provides: qa_start, qa_stop, qa_send, qa_keys, qa_screen, qa_screenshot,
#           qa_assert_screen, qa_assert_not_screen, qa_assert_file,
#           qa_pass, qa_fail, qa_skip, qa_tmpfile, qa_cleanup
# ===========================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

QA_ZEPTO="${QA_ZEPTO:-./zepto}"
QA_SESSION="zqa_$$"
QA_RENDER_WAIT="${QA_RENDER_WAIT:-0.4}"
QA_TMPDIR=""
QA_PASSED=0
QA_FAILED=0
QA_SKIPPED=0
QA_TEST_NAME="${QA_TEST_NAME:-$(basename "$0" .sh)}"
QA_TIER="${QA_TIER:-1}"

# Colors for output
_RED=$'\033[31m'
_GREEN=$'\033[32m'
_YELLOW=$'\033[33m'
_CYAN=$'\033[36m'
_DIM=$'\033[2m'
_RESET=$'\033[0m'

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

# Create a temp directory for this test run
qa_setup() {
    QA_TMPDIR=$(mktemp -d /tmp/zepto_qa_XXXXXX)
    # Ensure hangon is available
    if ! command -v hangon &>/dev/null; then
        echo "${_RED}ERROR: hangon not found in PATH. Install: brew install joewalnes/tap/hangon${_RESET}" >&2
        exit 1
    fi
    # Ensure zepto binary exists
    if [[ ! -x "$QA_ZEPTO" ]]; then
        echo "${_RED}ERROR: $QA_ZEPTO not found or not executable. Run 'make build' first.${_RESET}" >&2
        exit 1
    fi
    # Clean stale sessions with our prefix
    hangon stop "$QA_SESSION" 2>/dev/null || true
}

# Clean up temp files and sessions
qa_cleanup() {
    hangon stop "$QA_SESSION" 2>/dev/null || true
    if [[ -n "$QA_TMPDIR" && -d "$QA_TMPDIR" ]]; then
        rm -rf "$QA_TMPDIR"
    fi
}
trap qa_cleanup EXIT

# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

# Start zepto in a hangon session
#   qa_start [args...]
# Example: qa_start /tmp/test.txt
#          qa_start --no-nerd-font /tmp/test.txt
qa_start() {
    hangon start process --name "$QA_SESSION" -- "$QA_ZEPTO" "$@"
    sleep "$QA_RENDER_WAIT"
}

# Stop the current session
qa_stop() {
    hangon stop "$QA_SESSION" 2>/dev/null || true
}

# Check if session is alive (exit 0 = alive)
qa_alive() {
    hangon alive "$QA_SESSION" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

# Type literal text
qa_send() {
    hangon send "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# Send special keys (ctrl-a, enter, escape, etc.)
qa_keys() {
    hangon keys "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# Send raw bytes (for key combos not in hangon's key map)
#   qa_raw $'\x1b[32;5u'
qa_raw() {
    hangon send "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# Send raw bytes from stdin (for NUL bytes or binary data)
#   printf '\x00' | qa_raw_stdin
qa_raw_stdin() {
    hangon send "$QA_SESSION" --stdin
    sleep "${1:-$QA_RENDER_WAIT}"
}

# Send a line of text (text + enter)
qa_sendline() {
    hangon sendline "$QA_SESSION" "$1"
    sleep "${2:-$QA_RENDER_WAIT}"
}

# Wait for a regex pattern to appear on screen (with timeout)
qa_expect() {
    local pattern="$1"
    local timeout="${2:-5}"
    if ! hangon expect "$QA_SESSION" "$pattern" --timeout "$timeout" 2>/dev/null; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Screen capture
# ---------------------------------------------------------------------------

# Capture current screen as text, store in $QA_SCREEN
QA_SCREEN=""
qa_screen() {
    QA_SCREEN=$(hangon screen "$QA_SESSION" 2>/dev/null || echo "")
}

# Capture screen as PNG screenshot
#   qa_screenshot /path/to/file.png
qa_screenshot() {
    hangon screenshot "$QA_SESSION" "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

# Assert screen contains a pattern (grep -E)
#   qa_assert_screen "pattern" "description"
qa_assert_screen() {
    local pattern="$1"
    local desc="${2:-screen contains '$pattern'}"
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "$pattern"; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Pattern not found: $pattern"
    fi
}

# Assert screen does NOT contain a pattern
qa_assert_not_screen() {
    local pattern="$1"
    local desc="${2:-screen does not contain '$pattern'}"
    qa_screen
    if echo "$QA_SCREEN" | grep -qE "$pattern"; then
        qa_fail "$desc" "Pattern unexpectedly found: $pattern"
    else
        qa_pass "$desc"
    fi
}

# Assert a file exists on disk
qa_assert_file_exists() {
    local path="$1"
    local desc="${2:-file exists: $path}"
    if [[ -f "$path" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "File not found: $path"
    fi
}

# Assert a file contains a pattern
qa_assert_file_contains() {
    local path="$1"
    local pattern="$2"
    local desc="${3:-file '$path' contains '$pattern'}"
    if grep -qE "$pattern" "$path" 2>/dev/null; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Pattern not found in file"
    fi
}

# Assert a file does NOT contain a pattern
qa_assert_file_not_contains() {
    local path="$1"
    local pattern="$2"
    local desc="${3:-file '$path' does not contain '$pattern'}"
    if grep -qE "$pattern" "$path" 2>/dev/null; then
        qa_fail "$desc" "Pattern unexpectedly found in file"
    else
        qa_pass "$desc"
    fi
}

# Assert exit code of last command
qa_assert_exit() {
    local expected="$1"
    local actual="$2"
    local desc="${3:-exit code is $expected}"
    if [[ "$actual" -eq "$expected" ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "Expected exit $expected, got $actual"
    fi
}

# Assert the session is no longer alive (editor exited)
qa_assert_exited() {
    local desc="${1:-editor has exited}"
    sleep 0.3
    if qa_alive 2>/dev/null; then
        qa_fail "$desc" "Session still alive"
    else
        qa_pass "$desc"
    fi
}

# ---------------------------------------------------------------------------
# Results reporting
# ---------------------------------------------------------------------------

qa_pass() {
    local desc="$1"
    echo "  ${_GREEN}PASS${_RESET} $desc"
    QA_PASSED=$((QA_PASSED + 1))
}

qa_fail() {
    local desc="$1"
    local detail="${2:-}"
    echo "  ${_RED}FAIL${_RESET} $desc"
    if [[ -n "$detail" ]]; then
        echo "       ${_DIM}$detail${_RESET}"
    fi
    # Dump screen for debugging
    if [[ -n "$QA_SCREEN" ]]; then
        echo "       ${_DIM}--- screen snapshot ---${_RESET}"
        echo "$QA_SCREEN" | head -5 | sed 's/^/       /'
        echo "       ${_DIM}...${_RESET}"
    fi
    QA_FAILED=$((QA_FAILED + 1))
}

qa_skip() {
    local desc="$1"
    local reason="${2:-}"
    echo "  ${_YELLOW}SKIP${_RESET} $desc${reason:+ ($reason)}"
    QA_SKIPPED=$((QA_SKIPPED + 1))
}

# Print test header
qa_header() {
    echo "${_CYAN}[$QA_TEST_NAME]${_RESET} $1"
}

# Print summary and exit with appropriate code
qa_summary() {
    echo ""
    local total=$((QA_PASSED + QA_FAILED + QA_SKIPPED))
    if [[ $QA_FAILED -eq 0 ]]; then
        echo "${_GREEN}$QA_TEST_NAME: $QA_PASSED passed${_RESET}${QA_SKIPPED:+, $QA_SKIPPED skipped} (of $total)"
    else
        echo "${_RED}$QA_TEST_NAME: $QA_FAILED FAILED${_RESET}, $QA_PASSED passed${QA_SKIPPED:+, $QA_SKIPPED skipped} (of $total)"
    fi
    [[ $QA_FAILED -eq 0 ]]
}

# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------

# Create a temp file with content, return its path
#   path=$(qa_tmpfile "filename.txt" "content here")
qa_tmpfile() {
    local name="$1"
    local content="${2:-}"
    local path="$QA_TMPDIR/$name"
    mkdir -p "$(dirname "$path")"
    printf '%s' "$content" > "$path"
    echo "$path"
}

# Create a temp file with content ending in newline
qa_tmpfile_nl() {
    local name="$1"
    local content="${2:-}"
    local path="$QA_TMPDIR/$name"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "$path"
}

# ---------------------------------------------------------------------------
# LLM judge (Tier 2)
# ---------------------------------------------------------------------------

# Check if LLM judging is available
qa_llm_available() {
    if [[ "${ZEPTO_QA_SKIP_LLM:-0}" == "1" ]]; then
        return 1
    fi
    if [[ -z "${ZEPTO_QA_API_KEY:-}" && -z "${ANTHROPIC_API_KEY:-}" && -z "${OPENAI_API_KEY:-}" ]]; then
        return 1
    fi
    return 0
}

# Judge a screenshot with an LLM
#   result=$(qa_llm_judge /path/to/screenshot.png "prompt question")
# Returns "PASS" or "FAIL: reason"
qa_llm_judge() {
    local screenshot="$1"
    local prompt="$2"
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    "$script_dir/llm-judge.sh" "$screenshot" "$prompt"
}

# Assert LLM judges screenshot as passing
qa_assert_visual() {
    local screenshot="$1"
    local prompt="$2"
    local desc="${3:-visual check: $prompt}"

    if ! qa_llm_available; then
        qa_skip "$desc" "LLM not configured"
        return
    fi

    local result
    result=$(qa_llm_judge "$screenshot" "$prompt") || true
    if [[ "$result" == PASS* ]]; then
        qa_pass "$desc"
    else
        qa_fail "$desc" "$result"
    fi
}

# ---------------------------------------------------------------------------
# Init
# ---------------------------------------------------------------------------
qa_setup
