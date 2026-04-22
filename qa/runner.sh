#!/usr/bin/env bash
# ===========================================================================
# runner.sh — Zepto QA test runner
# ===========================================================================
# Discovers and runs QA test scripts in parallel, reports results.
#
# Usage:
#   qa/runner.sh                    # run tier 1 only (default)
#   qa/runner.sh --tier 1,2         # run tiers 1 and 2
#   qa/runner.sh --tier 1,2,3       # run all automated tiers
#   qa/runner.sh --filter edit      # run only scripts matching "edit"
#   qa/runner.sh --list             # list all scripts without running
#   qa/runner.sh --report FILE      # write results to file
#   qa/runner.sh --serial           # disable parallel execution
#   qa/runner.sh --jobs N           # max parallel jobs (default: 4)
#   qa/runner.sh scripts/tier1/foo  # run a single script
#
# Environment:
#   QA_ZEPTO              — path to zepto binary (default: ./zepto)
#   ZEPTO_QA_SKIP_LLM=1   — skip all LLM visual checks
#   ZEPTO_QA_API_KEY       — API key for LLM visual checks
#   ZEPTO_QA_API_URL       — API endpoint (default: Anthropic)
#   ZEPTO_QA_MODEL         — model for visual checks
# ===========================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QA_DIR="$SCRIPT_DIR"
TIERS="1"
FILTER=""
LIST_ONLY=0
REPORT_FILE=""
SINGLE_SCRIPT=""
PARALLEL=1
MAX_JOBS=4

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tier)
            TIERS="$2"; shift 2 ;;
        --filter)
            FILTER="$2"; shift 2 ;;
        --list)
            LIST_ONLY=1; shift ;;
        --report)
            REPORT_FILE="$2"; shift 2 ;;
        --serial)
            PARALLEL=0; shift ;;
        --jobs)
            MAX_JOBS="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: runner.sh [--tier 1,2,3] [--filter PATTERN] [--list] [--report FILE] [--serial] [--jobs N] [SCRIPT]"
            exit 0 ;;
        *)
            SINGLE_SCRIPT="$1"; shift ;;
    esac
done

# Colors
_RED=$'\033[31m'
_GREEN=$'\033[32m'
_YELLOW=$'\033[33m'
_CYAN=$'\033[36m'
_BOLD=$'\033[1m'
_DIM=$'\033[2m'
_RESET=$'\033[0m'

# ---------------------------------------------------------------------------
# Discover scripts
# ---------------------------------------------------------------------------

discover_scripts() {
    local scripts=()

    if [[ -n "$SINGLE_SCRIPT" ]]; then
        if [[ -f "$QA_DIR/$SINGLE_SCRIPT" ]]; then
            scripts+=("$QA_DIR/$SINGLE_SCRIPT")
        elif [[ -f "$SINGLE_SCRIPT" ]]; then
            scripts+=("$SINGLE_SCRIPT")
        else
            echo "${_RED}Script not found: $SINGLE_SCRIPT${_RESET}" >&2
            exit 1
        fi
    else
        IFS=',' read -ra TIER_LIST <<< "$TIERS"
        for tier in "${TIER_LIST[@]}"; do
            local dir="$QA_DIR/scripts/tier${tier}"
            if [[ -d "$dir" ]]; then
                while IFS= read -r -d '' script; do
                    scripts+=("$script")
                done < <(find "$dir" -name '*.sh' -type f -print0 | sort -z)
            fi
        done
    fi

    if [[ -n "$FILTER" ]]; then
        local filtered=()
        for s in "${scripts[@]}"; do
            if [[ "$(basename "$s")" == *"$FILTER"* ]]; then
                filtered+=("$s")
            fi
        done
        scripts=("${filtered[@]}")
    fi

    printf '%s\n' "${scripts[@]}"
}

# ---------------------------------------------------------------------------
# Discover
# ---------------------------------------------------------------------------

scripts=$(discover_scripts)

if [[ -z "$scripts" ]]; then
    echo "${_YELLOW}No test scripts found for tier(s) $TIERS${FILTER:+ matching '$FILTER'}.${_RESET}"
    exit 0
fi

TOTAL=$(echo "$scripts" | wc -l | tr -d ' ')

if [[ "$LIST_ONLY" -eq 1 ]]; then
    echo "${_BOLD}QA scripts (tier $TIERS):${_RESET}"
    echo "$scripts" | while read -r s; do
        echo "  $(basename "$s")"
    done
    echo "${_DIM}$TOTAL scripts${_RESET}"
    exit 0
fi

# Single script = always serial
if [[ -n "$SINGLE_SCRIPT" ]]; then
    PARALLEL=0
fi

# Header
echo ""
echo "${_BOLD}Zepto QA Test Run${_RESET}"
mode_info="Tiers: $TIERS"
if [[ $PARALLEL -eq 1 ]]; then
    mode_info="$mode_info | Parallel (max $MAX_JOBS)"
else
    mode_info="$mode_info | Serial"
fi
echo "${_DIM}${mode_info}${FILTER:+ | Filter: $FILTER}${_RESET}"
echo "${_DIM}$(date '+%Y-%m-%d %H:%M:%S')${_RESET}"
echo "─────────────────────────────────────────"
echo ""

RUN_START=$(date +%s)

# Tee output to report if requested
if [[ -n "$REPORT_FILE" ]]; then
    mkdir -p "$(dirname "$REPORT_FILE")"
    exec > >(tee "$REPORT_FILE") 2>&1
fi

# Ensure clean hangon state
hangon stopall 2>/dev/null || true

# ---------------------------------------------------------------------------
# Run scripts
# ---------------------------------------------------------------------------

# Strip ANSI escape codes for reliable pattern matching
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

RESULTS_DIR=$(mktemp -d /tmp/zepto_qa_results_XXXXXX)
trap 'rm -rf "$RESULTS_DIR"; hangon stopall 2>/dev/null || true' EXIT

run_script() {
    local script="$1"
    local index="$2"
    local script_name
    script_name=$(basename "$script" .sh)
    local out_file="$RESULTS_DIR/${index}_${script_name}.out"
    local rc_file="$RESULTS_DIR/${index}_${script_name}.rc"
    local time_file="$RESULTS_DIR/${index}_${script_name}.time"

    local start_time
    start_time=$(date +%s)

    set +e
    bash "$script" > "$out_file" 2>&1
    echo $? > "$rc_file"
    set -e

    local end_time
    end_time=$(date +%s)
    echo $((end_time - start_time)) > "$time_file"
}

if [[ $PARALLEL -eq 1 ]]; then
    # -----------------------------------------------------------------------
    # Parallel execution
    # -----------------------------------------------------------------------
    PIDS=()
    INDEX=0
    SCRIPT_NAMES=()
    SCRIPT_INDICES=()

    while IFS= read -r script; do
        INDEX=$((INDEX + 1))
        script_name=$(basename "$script" .sh)
        SCRIPT_NAMES+=("$script_name")
        SCRIPT_INDICES+=("$INDEX")

        run_script "$script" "$INDEX" &
        PIDS+=($!)

        # Throttle to MAX_JOBS
        while [[ $(jobs -r | wc -l) -ge $MAX_JOBS ]]; do
            sleep 0.1
        done
    done <<< "$scripts"

    # Wait for all, printing results as they complete
    REPORTED=()
    for i in "${!PIDS[@]}"; do
        REPORTED[$i]=0
    done

    DONE=0
    while [[ $DONE -lt $TOTAL ]]; do
        sleep 0.2
        for i in "${!PIDS[@]}"; do
            [[ "${REPORTED[$i]}" -eq 1 ]] && continue
            idx="${SCRIPT_INDICES[$i]}"
            name="${SCRIPT_NAMES[$i]}"
            rc_file="$RESULTS_DIR/${idx}_${name}.rc"
            if [[ -f "$rc_file" ]]; then
                REPORTED[$i]=1
                DONE=$((DONE + 1))
                rc=$(cat "$rc_file")
                time_file="$RESULTS_DIR/${idx}_${name}.time"
                elapsed=$(cat "$time_file" 2>/dev/null || echo "?")
                if [[ "$rc" -eq 0 ]]; then
                    echo " ${_GREEN}✓${_RESET} ${name} ${_DIM}(${elapsed}s)${_RESET} ${_DIM}[${DONE}/${TOTAL}]${_RESET}"
                else
                    echo " ${_RED}✗${_RESET} ${name} ${_DIM}(${elapsed}s)${_RESET} ${_DIM}[${DONE}/${TOTAL}]${_RESET}"
                fi
            fi
        done
    done

    # Collect totals and failure details
    TOTAL_PASS=0
    TOTAL_FAIL=0
    TOTAL_SKIP=0
    TOTAL_ERR=0
    FAILED_SCRIPTS=()

    for i in "${!SCRIPT_NAMES[@]}"; do
        idx="${SCRIPT_INDICES[$i]}"
        name="${SCRIPT_NAMES[$i]}"
        out_file="$RESULTS_DIR/${idx}_${name}.out"
        rc_file="$RESULTS_DIR/${idx}_${name}.rc"
        rc=$(cat "$rc_file")
        output=$(cat "$out_file")

        script_pass=$(echo "$output" | strip_ansi | grep -c "  PASS " || true)
        script_fail=$(echo "$output" | strip_ansi | grep -c "  FAIL " || true)
        script_skip=$(echo "$output" | strip_ansi | grep -c "  SKIP " || true)

        TOTAL_PASS=$((TOTAL_PASS + script_pass))
        TOTAL_FAIL=$((TOTAL_FAIL + script_fail))
        TOTAL_SKIP=$((TOTAL_SKIP + script_skip))

        if [[ $rc -ne 0 && $script_fail -eq 0 ]]; then
            TOTAL_ERR=$((TOTAL_ERR + 1))
            FAILED_SCRIPTS+=("$name (error)")
        elif [[ $script_fail -gt 0 ]]; then
            FAILED_SCRIPTS+=("$name")
        fi

        # Show failure details
        if [[ $rc -ne 0 || $script_fail -gt 0 ]]; then
            echo "$output" | strip_ansi | grep -E "  (FAIL|ERROR) " | sed 's/^/     /'
        fi
    done

else
    # -----------------------------------------------------------------------
    # Serial execution
    # -----------------------------------------------------------------------
    TOTAL_PASS=0
    TOTAL_FAIL=0
    TOTAL_SKIP=0
    TOTAL_ERR=0
    FAILED_SCRIPTS=()
    INDEX=0

    while IFS= read -r script; do
        INDEX=$((INDEX + 1))
        script_name=$(basename "$script" .sh)

        echo "${_CYAN}━━━ ${script_name} ━━━${_RESET} ${_DIM}[$INDEX/$TOTAL]${_RESET}"

        set +e
        output=$(bash "$script" 2>&1)
        exit_code=$?
        set -e

        echo "$output"

        script_pass=$(echo "$output" | strip_ansi | grep -c "  PASS " || true)
        script_fail=$(echo "$output" | strip_ansi | grep -c "  FAIL " || true)
        script_skip=$(echo "$output" | strip_ansi | grep -c "  SKIP " || true)

        TOTAL_PASS=$((TOTAL_PASS + script_pass))
        TOTAL_FAIL=$((TOTAL_FAIL + script_fail))
        TOTAL_SKIP=$((TOTAL_SKIP + script_skip))

        if [[ $exit_code -ne 0 && $script_fail -eq 0 ]]; then
            echo "  ${_RED}ERROR${_RESET} script exited with code $exit_code"
            TOTAL_ERR=$((TOTAL_ERR + 1))
            FAILED_SCRIPTS+=("$script_name (error)")
        elif [[ $script_fail -gt 0 ]]; then
            FAILED_SCRIPTS+=("$script_name")
        fi

        echo ""
    done <<< "$scripts"
fi

# Cleanup
hangon stopall 2>/dev/null || true

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

RUN_END=$(date +%s)
RUN_ELAPSED=$((RUN_END - RUN_START))

echo ""
echo "═══════════════════════════════════════════"
echo "${_BOLD}QA Summary${_RESET} ${_DIM}(${RUN_ELAPSED}s)${_RESET}"
echo "─────────────────────────────────────────"
echo "  Scripts: $TOTAL"
echo "  ${_GREEN}Passed:  $TOTAL_PASS${_RESET}"
if [[ $TOTAL_FAIL -gt 0 ]]; then
    echo "  ${_RED}Failed:  $TOTAL_FAIL${_RESET}"
else
    echo "  Failed:  0"
fi
if [[ $TOTAL_SKIP -gt 0 ]]; then
    echo "  ${_YELLOW}Skipped: $TOTAL_SKIP${_RESET}"
fi
if [[ $TOTAL_ERR -gt 0 ]]; then
    echo "  ${_RED}Errors:  $TOTAL_ERR${_RESET}"
fi
echo ""

if [[ ${#FAILED_SCRIPTS[@]} -gt 0 ]]; then
    echo "${_RED}Failed scripts:${_RESET}"
    for s in "${FAILED_SCRIPTS[@]}"; do
        echo "  - $s"
    done
    echo ""
fi

if [[ -n "$REPORT_FILE" ]]; then
    echo "${_DIM}Report: $REPORT_FILE${_RESET}"
fi

if [[ $TOTAL_FAIL -eq 0 && $TOTAL_ERR -eq 0 ]]; then
    echo "${_GREEN}${_BOLD}ALL PASSED${_RESET}"
    exit 0
else
    echo "${_RED}${_BOLD}FAILURES DETECTED${_RESET}"
    exit 1
fi
